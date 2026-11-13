# Métricas de calidad de datos

Generado por `scripts/profile_quality.py` contra Snowflake (PSET2).

| Dimensión | Métrica | Resultado |
|---|---|---|
| Unicidad | Filas de comprobantes en RAW vs ids distintos (reproceso de 7 días) | 7546 / 7346 / 200 |
| Unicidad | Líneas en RAW vs ids distintos | 20209 / 19550 / 659 |
| Unicidad | Feriados de la API con fecha repetida | 1 |
| Completitud | Comprobantes completados sin cliente identificado (% consumidor final) | 5288 / 6907 / 76.6 |
| Completitud | Consumos de lote con costo unitario 0 (%) | 17111 / 19501 / 87.7 |
| Completitud | Líneas vendidas con costo real completo (%) | 2389 / 19504 / 12.2 |
| Completitud | Última venta registrada por sucursal | 1: 2026-11-12 · 2: 2026-11-12 · 3: 2026-08-27 |
| Completitud | Horas abiertas de la OBT sin ventas (ceros explícitos) | 132 / 1542 / 8.6 |
| Validez | Comprobantes anulados en la ventana | 16 / 6923 / 0.23 |
| Validez | Ventas fuera del horario declarado, matriz (fuera / gracia de cierre / total) | 8 / 113 / 5281 |
| Validez | Ventas fuera del horario declarado, sucursal 2 (fuera / gracia / total) | 16 / 17 / 1579 |
| Validez | Líneas con devolución | 8 / 19550 |
| Consistencia | Comprobantes cuyo subtotal no cuadra con la suma de líneas | 31 / 6907 / 230.54 |
| Consistencia | Comprobantes procesados antes de ser creados | 4 |
| Consistencia | Ventas cuya FECHA cambia al pasar de UTC a hora local (19:00-23:59 local) | 118 / 7324 |
| Consistencia | Horario del ERP de la matriz (L-V / sábado / domingo) | 08:00:00-18:00:00 / 09:00:00-17:00:00 / sin horario |
| Consistencia | Vendedores distintos con ventas en la matriz (incluye administración) | 6 / 5 |
| Consistencia | Vendedores distintos por día (sin administración), matriz: lun / mar-sáb / dom | 1.18 / 1.95 / 0.91 |
| Precisión | Ticket: mediana / p99 / máximo (USD) | 8.50000 / 107.08 / 771.37 |
| Precisión | Líneas cuyo subtotal != precio x cantidad - descuento | 0 / 19550 |
| Precisión | Margen bruto sobre líneas con costo (%) | 44.8 |
| Carga | Conciliación extraídas vs cargadas (corridas con diferencia) | 0 / 49 |
