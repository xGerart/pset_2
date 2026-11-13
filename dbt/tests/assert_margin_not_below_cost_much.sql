{{ config(severity='warn') }}
-- Precisión: una línea vendida muy por debajo del costo (margen < -50 %) suele ser un costo o
-- un precio mal cargado. Warn: se revisa, no detiene el pipeline.
select sales_line_id, net_amount, cost_amount, margin_amount
from {{ ref('fct_sales_lines') }}
where has_cost and net_amount > 0 and margin_amount / net_amount < -0.5
