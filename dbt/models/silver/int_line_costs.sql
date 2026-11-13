-- Costo por comprobante y producto a partir del consumo de lotes.
--  D-Q3 unit_cost = 0 viene del conteo inicial de inventario (stock sin costo de compra registrado):
--       no es un costo real. Se trata como desconocido; el margen solo se calcula si TODAS las
--       unidades vendidas de la línea tienen costo.
with consumption as (
    select *
    from {{ ref('stg_erp__batch_consumption') }}
    qualify row_number() over (partition by consumption_id order by _loaded_at desc, _run_id desc) = 1
)

select
    voucher_id,
    product_id,
    sum(quantity - coalesce(returned_quantity, 0))                                   as units_consumed,
    sum(iff(unit_cost > 0, quantity - coalesce(returned_quantity, 0), 0))            as units_with_cost,
    sum(iff(unit_cost > 0, (quantity - coalesce(returned_quantity, 0)) * unit_cost, 0)) as known_cost_amount,
    units_with_cost = units_consumed and units_consumed > 0                         as has_full_cost
from consumption
group by voucher_id, product_id
