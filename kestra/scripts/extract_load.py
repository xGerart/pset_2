"""Extracción (ERP por SSH + API de feriados) y carga a Snowflake RAW.

Diseño:
- RAW es append-only: cada corrida agrega filas con metadatos de carga
  (_batch_start, _batch_end, _loaded_at, _source_file, _run_id). Nunca se
  actualiza ni se borra. La deduplicación (quedarse con la versión más
  reciente de cada id) es una decisión de limpieza y vive en dbt (Silver).
- Las columnas llegan como VARCHAR: RAW guarda el dato tal como vino; los
  tipos se aplican en Bronze.
- Contrato de datos: si el encabezado del CSV no coincide con lo esperado,
  la carga falla en voz alta en vez de cargar columnas corridas.
- Conciliación: se compara filas extraídas vs filas cargadas por COPY y se
  registra en RAW.LOAD_AUDIT.

Uso:
  python extract_load.py --start 2026-08-20 --end 2026-11-07
  python extract_load.py --lookback-days 7          # corrida diaria
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

import requests
import snowflake.connector
from cryptography.hazmat.primitives import serialization

TZ_NOTE = "Fechas de ventana = fecha local (America/Guayaquil) de creación del comprobante"

# Contrato: entidad -> columnas esperadas, en orden.
WINDOWED = {
    "vouchers": [
        "id", "branch_id", "status", "created_at", "processed_at", "cancelled_at",
        "salesperson_id", "processed_by_id", "created_by_id", "customer_document_type",
        "has_customer_id", "subtotal", "discount", "total", "shipping_amount",
        "requires_comprobante", "has_coupon",
    ],
    "voucher_items": [
        "id", "voucher_id", "product_id", "sku_id", "conversion_factor", "quantity",
        "base_units", "free_units", "unit_price", "unit_price_original", "discount",
        "subtotal", "returned_quantity", "created_at",
    ],
    "batch_consumption": [
        "id", "voucher_id", "product_id", "branch_id", "batch_id", "quantity",
        "unit_cost", "returned_quantity", "created_at",
    ],
}
SNAPSHOTS = {
    "branches": [
        "id", "name", "branch_type", "is_active",
        "horario_lunes_viernes_inicio", "horario_lunes_viernes_fin",
        "horario_sabado_inicio", "horario_sabado_fin",
        "horario_domingo_inicio", "horario_domingo_fin", "created_at", "updated_at",
    ],
    "products": [
        "id", "name", "category_id", "brand_id", "product_type", "unit_type", "sale_price",
        "is_active", "is_for_sale", "is_kit", "created_at", "updated_at",
    ],
    "categories": ["id", "name"],
    "staff": ["id", "is_active", "roles"],
}
HOLIDAY_COLUMNS = ["date", "local_name", "name", "country_code", "is_global", "types"]
NAGER_URL = "https://date.nager.at/api/v3/PublicHolidays/{year}/EC"

META_COLUMNS = ["_batch_start", "_batch_end", "_loaded_at", "_source_file", "_run_id"]


class ContractError(RuntimeError):
    """El origen cambió de forma: no se reintenta, se corrige el contrato."""


def env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Falta la variable de entorno {name}")
    return value


# ---------------------------------------------------------------- fuentes
def ssh_extract(entity: str, start: dt.date | None, end: dt.date | None) -> bytes:
    """Ejecuta el extractor remoto (forced command) y devuelve el CSV."""
    workdir = Path(tempfile.mkdtemp())
    key = workdir / "id"
    key.write_text(env("ERP_SSH_KEY").strip() + "\n")
    key.chmod(0o600)
    known_hosts = workdir / "known_hosts"
    known_hosts.write_text(env("ERP_SSH_KNOWN_HOSTS").strip() + "\n")

    remote = entity if start is None else f"{entity} {start} {end}"
    cmd = [
        "ssh", "-i", str(key), "-o", "IdentitiesOnly=yes",
        "-o", f"UserKnownHostsFile={known_hosts}", "-o", "StrictHostKeyChecking=yes",
        "-o", "ConnectTimeout=20", "-o", "BatchMode=yes",
        f"{env('ERP_SSH_USER')}@{env('ERP_SSH_HOST')}", remote,
    ]
    result = subprocess.run(cmd, capture_output=True, timeout=300)
    if result.returncode != 0:
        raise RuntimeError(f"ssh {remote!r} falló ({result.returncode}): {result.stderr.decode()[:500]}")
    return result.stdout


def fetch_holidays(years: list[int]) -> bytes:
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(HOLIDAY_COLUMNS)
    for year in years:
        resp = requests.get(NAGER_URL.format(year=year), timeout=30)
        resp.raise_for_status()
        for h in resp.json():
            writer.writerow([h["date"], h["localName"], h["name"], h["countryCode"],
                             h["global"], ",".join(h.get("types") or [])])
    return out.getvalue().encode()


def check_contract(entity: str, payload: bytes, expected: list[str]) -> int:
    reader = csv.reader(io.StringIO(payload.decode("utf-8")))
    header = next(reader, None)
    if header != expected:
        raise ContractError(f"{entity}: encabezado {header} != contrato {expected}")
    return sum(1 for _ in reader)


# ---------------------------------------------------------------- Snowflake
def connect():
    pem = os.environ.get("SNOWFLAKE_PRIVATE_KEY") or Path(env("SNOWFLAKE_PRIVATE_KEY_FILE")).read_text()
    key = serialization.load_pem_private_key(pem.encode(), password=None)
    der = key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    return snowflake.connector.connect(
        account=env("SNOWFLAKE_ACCOUNT"), user=env("SNOWFLAKE_USER"), private_key=der,
        role=env("SNOWFLAKE_ROLE"), warehouse=env("SNOWFLAKE_WAREHOUSE"),
        database=env("SNOWFLAKE_DATABASE"), schema="RAW",
        session_parameters={"QUERY_TAG": "pset2-ingest", "TIMEZONE": "UTC"},
    )


def ensure_tables(cur, table: str, columns: list[str]) -> None:
    cols = ", ".join(f'"{c.upper()}" VARCHAR' for c in columns)
    cur.execute(
        f"CREATE TABLE IF NOT EXISTS RAW.{table} ({cols}, "
        "_BATCH_START DATE, _BATCH_END DATE, _LOADED_AT TIMESTAMP_TZ, "
        "_SOURCE_FILE VARCHAR, _RUN_ID VARCHAR)"
    )
    cur.execute(
        "CREATE TABLE IF NOT EXISTS RAW.LOAD_AUDIT (RUN_ID VARCHAR, ENTITY VARCHAR, "
        "BATCH_START DATE, BATCH_END DATE, ROWS_EXTRACTED NUMBER, ROWS_LOADED NUMBER, "
        "LOADED_AT TIMESTAMP_TZ)"
    )


def load(cur, entity: str, columns: list[str], payload: bytes, rows: int,
         start: dt.date, end: dt.date, run_id: str) -> None:
    table = ("NAGER_HOLIDAYS" if entity == "holidays" else f"ERP_{entity.upper()}")
    ensure_tables(cur, table, columns)
    fname = f"{entity}_{start}_{end}_{run_id}.csv"
    path = Path(tempfile.mkdtemp()) / fname
    path.write_bytes(payload)

    cur.execute(f"PUT 'file://{path}' @RAW.%{table}/{run_id}/ AUTO_COMPRESS=TRUE OVERWRITE=TRUE")
    select = ", ".join(f"${i}" for i in range(1, len(columns) + 1))
    target = ", ".join(f'"{c.upper()}"' for c in columns + META_COLUMNS)
    cur.execute(
        f"COPY INTO RAW.{table} ({target}) FROM ("
        f"  SELECT {select}, '{start}'::DATE, '{end}'::DATE, CURRENT_TIMESTAMP(),"
        f"         METADATA$FILENAME, '{run_id}'"
        f"  FROM @RAW.%{table}/{run_id}/) "
        "FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '\"' "
        "               EMPTY_FIELD_AS_NULL = TRUE ENCODING = 'UTF8') "
        f"PATTERN = '.*{fname}.*' ON_ERROR = ABORT_STATEMENT"
    )
    loaded = sum(r[3] for r in cur.fetchall() if r[1] in ("LOADED", "LOAD_SKIPPED") and r[3] is not None) if rows else 0
    cur.execute(f"REMOVE @RAW.%{table}/{run_id}/")
    cur.execute(
        "INSERT INTO RAW.LOAD_AUDIT VALUES (%s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP())",
        (run_id, entity, str(start), str(end), rows, loaded),
    )
    if loaded != rows:
        raise RuntimeError(f"{entity} {start}..{end}: extraídas {rows} filas, cargadas {loaded}")
    print(f"  {entity:<18} {start}..{end}  {rows:>6} filas")


def chunks(start: dt.date, end: dt.date, days: int):
    cursor = start
    while cursor <= end:
        stop = min(cursor + dt.timedelta(days=days - 1), end)
        yield cursor, stop
        cursor = stop + dt.timedelta(days=1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", type=dt.date.fromisoformat)
    parser.add_argument("--end", type=dt.date.fromisoformat)
    parser.add_argument("--lookback-days", type=int, default=7,
                        help="si no hay --start/--end: recarga [hoy-N, ayer]")
    parser.add_argument("--chunk-days", type=int, default=7)
    parser.add_argument("--run-date", type=dt.date.fromisoformat,
                        help="fecha lógica de la corrida (la del trigger); por defecto hoy")
    args = parser.parse_args()

    run_date = args.run_date or dt.date.today()
    start = args.start or run_date - dt.timedelta(days=args.lookback_days)
    end = args.end or run_date - dt.timedelta(days=1)
    if start > end:
        raise SystemExit(f"Ventana vacía: {start} > {end}")
    run_id = os.environ.get("RUN_ID") or uuid.uuid4().hex[:12]
    print(f"Corrida {run_id}: ventana {start}..{end}. {TZ_NOTE}.")

    with connect() as conn, conn.cursor() as cur:
        for entity, columns in WINDOWED.items():
            for a, b in chunks(start, end, args.chunk_days):
                payload = ssh_extract(entity, a, b)
                load(cur, entity, columns, payload, check_contract(entity, payload, columns), a, b, run_id)
        for entity, columns in SNAPSHOTS.items():
            payload = ssh_extract(entity, None, None)
            load(cur, entity, columns, payload, check_contract(entity, payload, columns), run_date, run_date, run_id)
        years = sorted({start.year, end.year, run_date.year})
        payload = fetch_holidays(years)
        load(cur, "holidays", HOLIDAY_COLUMNS, payload,
             check_contract("holidays", payload, HOLIDAY_COLUMNS),
             dt.date(years[0], 1, 1), dt.date(years[-1], 12, 31), run_id)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ContractError as exc:
        print(f"ERROR DE CONTRATO (no reintentar sin revisar): {exc}", file=sys.stderr)
        sys.exit(2)
