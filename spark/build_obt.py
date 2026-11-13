"""OBT para el modelo de pronóstico: una fila por sucursal x fecha x hora ABIERTA.

Fuente: el star schema de GOLD (fct_store_hours como spine + fct_sales_lines + dims).
Destino: OBT.OBT_SALES_HOURLY (overwrite, idempotente) y OBT.OBT_AUDIT (validaciones).

Reglas:
- El spine son las horas abiertas: una hora abierta sin ventas vale 0; una cerrada no existe.
- Todos los joins son LEFT desde el spine, contra tablas agregadas al grano del spine
  o dimensiones con llave única, así que no pueden multiplicar filas. Igual se verifica.
- Las variables predictoras solo usan información de >= 7 días antes (sin leakage):
  el horario de la semana se decide antes de que empiece.
"""
from __future__ import annotations

import os
import sys
from datetime import date

from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql import functions as F

GRAIN = ["branch_id", "hour_date", "hour_of_day"]


def sf_options(schema: str) -> dict:
    pem = os.environ["SNOWFLAKE_PRIVATE_KEY"]
    body = "".join(l for l in pem.strip().splitlines() if "PRIVATE KEY" not in l)
    return {
        "sfURL": f"{os.environ['SNOWFLAKE_ACCOUNT']}.snowflakecomputing.com",
        "sfUser": os.environ["SNOWFLAKE_USER"],
        "pem_private_key": body,
        "sfRole": os.environ["SNOWFLAKE_ROLE"],
        "sfWarehouse": os.environ["SNOWFLAKE_WAREHOUSE"],
        "sfDatabase": os.environ["SNOWFLAKE_DATABASE"],
        "sfSchema": schema,
    }


def read(spark: SparkSession, table: str) -> DataFrame:
    df = (spark.read.format("snowflake").options(**sf_options("GOLD"))
          .option("dbtable", table).load())
    return df.toDF(*[c.lower() for c in df.columns])


def write(df: DataFrame, table: str) -> None:
    (df.write.format("snowflake").options(**sf_options("OBT"))
       .option("dbtable", table).mode("overwrite").save())


def main() -> int:
    start = date.fromisoformat(os.environ.get("ANALYSIS_START_DATE", "2026-08-20"))
    end = date.fromisoformat(os.environ.get("ANALYSIS_END_DATE", "2026-11-07"))
    spark = SparkSession.builder.appName("pset2-build-obt").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")

    # ---------------------------------------------------------------- lecturas
    store_hours = read(spark, "FCT_STORE_HOURS")
    sales = read(spark, "FCT_SALES_LINES")
    dim_date = read(spark, "DIM_DATE")
    dim_branch = read(spark, "DIM_BRANCH")
    dim_hour = read(spark, "DIM_HOUR")

    branches = dim_branch.filter(F.col("experiment_role").isin("tratamiento", "control"))
    dates = dim_date.filter(F.col("calendar_date").between(F.lit(start), F.lit(end)))

    # ---------------------------------------------------------------- spine
    spine = (store_hours
             .join(branches.select("branch_key", "branch_id", "branch_name", "experiment_role"),
                   "branch_key", "inner")
             .join(dates.select("date_key", F.col("calendar_date").alias("hour_date")),
                   "date_key", "inner")
             .withColumnRenamed("hour_key", "hour_of_day"))

    # ---------------------------------------------------------------- hechos al grano
    # Una venta = un comprobante. Se agrega por hora ANTES del join (grano del spine).
    hourly_sales = (sales
                    .filter(~F.col("is_outside_opening_hours"))
                    .groupBy("branch_key", "date_key", F.col("hour_key").alias("hour_of_day"))
                    .agg(F.countDistinct("voucher_id").alias("sales_count"),
                         F.sum("net_amount").alias("net_sales_amount"),
                         F.sum("net_quantity").alias("units_sold"),
                         F.countDistinct(F.when(F.col("is_admin_sale"), F.col("voucher_id"))).alias("admin_sales_count")))

    obt = (spine
           .join(hourly_sales, ["branch_key", "date_key", "hour_of_day"], "left")
           .join(dim_date.select("date_key", "iso_day_of_week", "day_name", "is_weekend", "iso_week",
                                 "week_start_date", "is_holiday", "holiday_name", "event_codes",
                                 "is_seasonal_event"),
                 "date_key", "left")
           .join(dim_hour.select(F.col("hour_key").alias("hour_of_day"), "hour_label", "day_part"),
                 "hour_of_day", "left")
           .fillna({"sales_count": 0, "net_sales_amount": 0.0, "units_sold": 0, "admin_sales_count": 0}))

    # ---------------------------------------------------------------- features sin leakage
    # Rezagos por FECHA (no por fila): misma sucursal y hora, 7/14/21/28 días antes. Si ese día
    # la tienda estaba cerrada (o antes del inicio de datos), el rezago queda NULL.
    lag_src = obt.select("branch_id", "hour_date", "hour_of_day", "sales_count")
    for k in (7, 14, 21, 28):
        lagged = lag_src.select(
            "branch_id", "hour_of_day",
            F.date_add("hour_date", k).alias("hour_date"),
            F.col("sales_count").alias(f"sales_lag_{k}d"))
        obt = obt.join(lagged, GRAIN, "left")
    lag_cols = [F.col(f"sales_lag_{k}d") for k in (7, 14, 21, 28)]
    n_lags = sum(F.when(c.isNotNull(), 1).otherwise(0) for c in lag_cols)
    lag_sum = sum(F.coalesce(c, F.lit(0)) for c in lag_cols)
    obt = obt.withColumn("sales_avg_4w_same_hour", F.when(n_lags > 0, lag_sum / n_lags))

    # Objetivo derivado (NO es predictor): carga por vendedor presente.
    obt = (obt
           .withColumn("load_per_staff",
                       F.when(F.col("staff_present") > 0, F.col("sales_count") / F.col("staff_present")))
           .withColumn("is_overloaded", F.col("load_per_staff") >= 8)
           .withColumn("obt_built_at", F.current_timestamp()))

    obt = obt.select(
        "branch_id", "branch_name", "experiment_role", "hour_date", "hour_of_day", "hour_label",
        "day_part", "iso_day_of_week", "day_name", "is_weekend", "iso_week", "week_start_date",
        "is_holiday", "holiday_name", "event_codes", "is_seasonal_event", "is_last_open_hour",
        "staff_present",
        "sales_count", "net_sales_amount", "units_sold", "admin_sales_count",
        "sales_lag_7d", "sales_lag_14d", "sales_lag_21d", "sales_lag_28d", "sales_avg_4w_same_hour",
        "load_per_staff", "is_overloaded", "obt_built_at",
    ).cache()

    # ---------------------------------------------------------------- validaciones
    spine_rows = spine.count()
    obt_rows = obt.count()
    dup_keys = obt.groupBy(*GRAIN).count().filter("count > 1").count()

    in_window_sales = (sales
                       .join(branches.select("branch_key"), "branch_key")
                       .join(dates.select("date_key"), "date_key"))
    gold_valid = in_window_sales.filter(~F.col("is_outside_opening_hours")).select("voucher_id").distinct().count()
    gold_outside = (in_window_sales.filter(F.col("is_outside_opening_hours"))
                    .select("voucher_id").distinct().count())
    obt_sales = obt.agg(F.sum("sales_count")).first()[0] or 0
    gold_amount = in_window_sales.filter(~F.col("is_outside_opening_hours")).agg(F.sum("net_amount")).first()[0] or 0
    obt_amount = obt.agg(F.sum("net_sales_amount")).first()[0] or 0
    # Un comprobante cae en una sola hora: si el join a horas hubiera perdido ventas
    # (hora de venta sin fila en el spine), sales_count sumaría menos que Gold.
    checks = [
        ("rows_equal_spine", spine_rows, obt_rows, spine_rows == obt_rows),
        ("grain_unique", 0, dup_keys, dup_keys == 0),
        ("sales_conserved", gold_valid, obt_sales, gold_valid == obt_sales),
        ("amount_conserved", round(float(gold_amount), 2), round(float(obt_amount), 2),
         abs(float(gold_amount) - float(obt_amount)) < 0.01),
        ("matriz_staff_not_null",
         0, obt.filter("experiment_role = 'tratamiento' and staff_present is null").count(), None),
        ("sales_outside_hours_excluded", gold_outside, gold_outside, True),
    ]
    checks = [(n, e, a, (a == 0) if ok is None else ok) for n, e, a, ok in checks]
    audit = spark.createDataFrame(
        [(n, str(e), str(a), bool(ok)) for n, e, a, ok in checks],
        "check_name string, expected string, actual string, passed boolean",
    ).withColumn("checked_at", F.current_timestamp())

    for n, e, a, ok in checks:
        print(f"[{'OK ' if ok else 'FAIL'}] {n:<30} esperado={e} obtenido={a}")

    write(audit, "OBT_AUDIT")
    if not all(ok for *_, ok in checks):
        print("Validación fallida: la OBT NO se publica.", file=sys.stderr)
        return 1
    write(obt, "OBT_SALES_HOURLY")
    print(f"OBT publicada: {obt_rows} filas ({start}..{end}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
