-- Completitud: la matriz y la sucursal de control nunca han tenido un día abierto sin ventas.
-- Un día abierto con 0 ventas indica casi seguro un hueco de ingesta, no demanda cero.
with open_days as (
    select distinct branch_id, hour_date
    from {{ ref('int_store_hours') }}
    where hour_date between '{{ var("analysis_start_date") }}' and least('{{ var("analysis_end_date") }}'::date, current_date - 1)
),
sales_days as (
    select distinct branch_id, sale_date from {{ ref('int_vouchers') }} where is_completed
)
select o.*
from open_days o
left join sales_days s on s.branch_id = o.branch_id and s.sale_date = o.hour_date
where s.sale_date is null
