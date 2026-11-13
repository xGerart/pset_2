-- Líneas deduplicadas (misma regla que los comprobantes) con cantidades netas de devolución.
select
    voucher_item_id,
    voucher_id,
    product_id,
    sku_id,
    conversion_factor,
    quantity,
    base_units,
    free_units,
    unit_price,
    unit_price_original,
    discount,
    subtotal,
    coalesce(returned_quantity, 0)                         as returned_quantity,
    quantity - coalesce(returned_quantity, 0)              as net_quantity,
    unit_price * quantity                                  as gross_amount,
    abs(unit_price * quantity - discount - subtotal) > 0.01 as is_line_amount_mismatch,
    _loaded_at
from {{ ref('stg_erp__voucher_items') }}
qualify row_number() over (partition by voucher_item_id order by _loaded_at desc, _run_id desc) = 1
