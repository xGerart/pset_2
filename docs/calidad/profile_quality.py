"""Perfilado de calidad sobre Snowflake (RAW y SILVER) -> docs/calidad/metricas.md.

Cada métrica es una consulta reproducible; el documento técnico cita estos números.
Uso (desde la raíz del repo):
  docker run --rm --env-file .env.runtime -v $PWD:/app -w /app pset2-runner:1.0 \
      python docs/calidad/profile_quality.py
"""
import sys
from pathlib import Path

sys.path.insert(0, "kestra/scripts")
from extract_load import connect  # noqa: E402

WINDOW = "sale_date between '2026-08-20' and '2026-11-07'"

METRICS = [
    # (dimensión, métrica, SQL que devuelve una fila con un valor o varios)
    ("Unicidad", "Filas de comprobantes en RAW vs ids distintos (reproceso de 7 días)",
     "select count(*), count(distinct id), count(*) - count(distinct id) from RAW.ERP_VOUCHERS"),
    ("Unicidad", "Líneas en RAW vs ids distintos",
     "select count(*), count(distinct id), count(*) - count(distinct id) from RAW.ERP_VOUCHER_ITEMS"),
    ("Unicidad", "Feriados de la API con fecha repetida",
     "select count(*) from (select \"DATE\" from RAW.NAGER_HOLIDAYS where _run_id = (select max(_run_id) from RAW.NAGER_HOLIDAYS) group by 1 having count(*) > 1)"),
    ("Completitud", "Comprobantes completados sin cliente identificado (% consumidor final)",
     f"select count_if(not has_customer_id), count(*), round(100 * count_if(not has_customer_id) / count(*), 1) from SILVER.INT_VOUCHERS where is_completed and {WINDOW}"),
    ("Completitud", "Consumos de lote con costo unitario 0 (%)",
     "select count_if(unit_cost = 0), count(*), round(100 * count_if(unit_cost = 0) / count(*), 1) from (select * from BRONZE.STG_ERP__BATCH_CONSUMPTION qualify row_number() over (partition by consumption_id order by _loaded_at desc) = 1)"),
    ("Completitud", "Líneas vendidas con costo real completo (%)",
     "select count_if(has_cost), count(*), round(100 * count_if(has_cost) / count(*), 1) from GOLD.FCT_SALES_LINES"),
    ("Completitud", "Última venta registrada por sucursal",
     "select listagg(branch_id || ': ' || last_day, ' · ') within group (order by branch_id) from (select branch_id, max(sale_date) as last_day from SILVER.INT_VOUCHERS where is_completed group by 1)"),
    ("Completitud", "Horas abiertas de la OBT sin ventas (ceros explícitos)",
     "select count_if(sales_count = 0), count(*), round(100 * count_if(sales_count = 0) / count(*), 1) from OBT.OBT_SALES_HOURLY"),
    ("Validez", "Comprobantes anulados en la ventana",
     f"select count_if(not is_completed), count(*), round(100 * count_if(not is_completed) / count(*), 2) from SILVER.INT_VOUCHERS where {WINDOW}"),
    ("Validez", "Ventas fuera del horario declarado, matriz (fuera / gracia de cierre / total)",
     f"select count_if(is_outside_opening_hours), count_if(is_post_close_grace), count(*) from SILVER.INT_VOUCHERS where is_completed and branch_id = 1 and {WINDOW}"),
    ("Validez", "Ventas fuera del horario declarado, sucursal 2 (fuera / gracia / total)",
     f"select count_if(is_outside_opening_hours), count_if(is_post_close_grace), count(*) from SILVER.INT_VOUCHERS where is_completed and branch_id = 2 and {WINDOW}"),
    ("Validez", "Líneas con devolución",
     "select count_if(returned_quantity > 0), count(*) from SILVER.INT_VOUCHER_ITEMS"),
    ("Consistencia", "Comprobantes cuyo subtotal no cuadra con la suma de líneas",
     f"select count_if(is_subtotal_mismatch), count(*), round(sum(iff(is_subtotal_mismatch, abs(subtotal - lines_subtotal), 0)), 2) from SILVER.INT_VOUCHERS where is_completed and {WINDOW}"),
    ("Consistencia", "Comprobantes procesados antes de ser creados",
     "select count_if(is_processed_before_created) from SILVER.INT_VOUCHERS"),
    ("Consistencia", "Ventas cuya FECHA cambia al pasar de UTC a hora local (19:00-23:59 local)",
     "select count_if(created_at_utc::date != created_at_local::date), count(*) from SILVER.INT_VOUCHERS where is_completed"),
    ("Consistencia", "Horario del ERP de la matriz (L-V / sábado / domingo)",
     "select erp_weekday_open || '-' || erp_weekday_close || ' / ' || erp_saturday_open || '-' || erp_saturday_close || ' / ' || coalesce(erp_sunday_open::varchar, 'sin horario') from SILVER.INT_BRANCHES where branch_id = 1"),
    ("Consistencia", "Vendedores distintos con ventas en la matriz (incluye administración)",
     f"select count(distinct salesperson_id), count(distinct iff(is_admin_sale, null, salesperson_id)) from SILVER.INT_VOUCHERS where is_completed and branch_id = 1 and {WINDOW}"),
    ("Consistencia", "Vendedores distintos por día (sin administración), matriz: lun / mar-sáb / dom",
     f"""select round(avg(iff(d = 1, n, null)), 2), round(avg(iff(d between 2 and 6, n, null)), 2), round(avg(iff(d = 7, n, null)), 2)
         from (select sale_date, dayofweekiso(sale_date) d, count(distinct iff(is_admin_sale, null, salesperson_id)) n
               from SILVER.INT_VOUCHERS where is_completed and branch_id = 1 and {WINDOW} group by 1, 2)"""),
    ("Precisión", "Ticket: mediana / p99 / máximo (USD)",
     f"select median(total), round(percentile_cont(0.99) within group (order by total), 2), max(total) from SILVER.INT_VOUCHERS where is_completed and {WINDOW}"),
    ("Precisión", "Líneas cuyo subtotal != precio x cantidad - descuento",
     "select count_if(is_line_amount_mismatch), count(*) from SILVER.INT_VOUCHER_ITEMS"),
    ("Precisión", "Margen bruto sobre líneas con costo (%)",
     "select round(100 * sum(margin_amount) / sum(net_amount), 1) from GOLD.FCT_SALES_LINES where has_cost"),
    ("Carga", "Conciliación extraídas vs cargadas (corridas con diferencia)",
     "select count_if(rows_extracted != rows_loaded), count(*) from RAW.LOAD_AUDIT"),
]


def main() -> None:
    lines = ["# Métricas de calidad de datos", "",
             "Generado por `docs/calidad/profile_quality.py` contra Snowflake (PSET2).", "",
             "| Dimensión | Métrica | Resultado |", "|---|---|---|"]
    with connect() as conn, conn.cursor() as cur:
        for dim, name, sql in METRICS:
            cur.execute(sql)
            row = cur.fetchone()
            value = " / ".join("—" if v is None else str(v) for v in row)
            print(f"{dim:<12} {name[:70]:<70} {value}")
            lines.append(f"| {dim} | {name} | {value} |")
    Path("docs/calidad/metricas.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
