-- Hecho transaccional. GRANO: una fila por línea de comprobante COMPLETADO (todas las sucursales).
-- Los anulados quedan fuera: no son demanda atendida (se cuantifican en Silver).
with v as (
    select * from {{ ref('int_vouchers') }} where is_completed
),
i as (
    select * from {{ ref('int_voucher_items') }}
),
c as (
    select * from {{ ref('int_line_costs') }}
)
select
    i.voucher_item_id                                                     as sales_line_id,
    i.voucher_id,                                                         -- dimensión degenerada
    to_number(to_char(v.sale_date, 'YYYYMMDD'))                           as date_key,
    coalesce(v.effective_hour, v.clock_hour)                              as hour_key,
    coalesce(b.branch_key, '-1')                                          as branch_key,
    coalesce(p.product_key, '-1')                                         as product_key,
    coalesce(sp.salesperson_key, '-1')                                    as salesperson_key,
    v.created_at_local                                                    as sold_at_local,
    v.is_outside_opening_hours,
    v.is_post_close_grace,
    v.is_admin_sale,
    -- medidas aditivas
    i.quantity,
    i.base_units,
    i.returned_quantity,
    i.net_quantity,
    i.gross_amount,
    i.discount                                                            as discount_amount,
    i.subtotal                                                            as net_amount,
    -- costo y margen solo cuando todas las unidades tienen costo real (D-Q3)
    coalesce(c.has_full_cost, false)                                      as has_cost,
    iff(c.has_full_cost, c.known_cost_amount * (i.net_quantity * i.conversion_factor)
                         / nullif(c.units_consumed, 0), null)             as cost_amount,
    iff(c.has_full_cost, i.subtotal - cost_amount, null)                  as margin_amount
from i
join v on v.voucher_id = i.voucher_id
left join {{ ref('dim_branch') }} b on b.branch_id = v.branch_id
left join {{ ref('dim_product') }} p on p.product_id = i.product_id
left join {{ ref('dim_salesperson') }} sp
       on sp.salesperson_key = {{ dbt_utils.generate_surrogate_key(['v.salesperson_id']) }}
left join c on c.voucher_id = i.voucher_id and c.product_id = i.product_id
