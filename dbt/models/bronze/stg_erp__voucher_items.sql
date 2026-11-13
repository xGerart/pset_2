select
    try_to_number(id)                            as voucher_item_id,
    try_to_number(voucher_id)                    as voucher_id,
    try_to_number(product_id)                    as product_id,
    try_to_number(sku_id)                        as sku_id,
    try_to_number(conversion_factor)             as conversion_factor,
    try_to_number(quantity)                      as quantity,
    try_to_number(base_units)                    as base_units,
    try_to_number(free_units)                    as free_units,
    try_to_decimal(unit_price, 12, 4)            as unit_price,
    try_to_decimal(unit_price_original, 12, 4)   as unit_price_original,
    try_to_decimal(discount, 12, 2)              as discount,
    try_to_decimal(subtotal, 12, 2)              as subtotal,
    try_to_number(returned_quantity)             as returned_quantity,
    {{ local_ts('created_at') }}                 as created_at_local,
    _loaded_at,
    _run_id
from {{ source('erp', 'erp_voucher_items') }}
