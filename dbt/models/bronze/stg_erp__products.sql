select
    try_to_number(id)                    as product_id,
    name                                 as product_name,
    try_to_number(category_id)           as category_id,
    try_to_number(brand_id)              as brand_id,
    product_type,
    unit_type,
    try_to_decimal(sale_price, 12, 2)    as sale_price,
    {{ pg_bool('is_active') }}           as is_active,
    {{ pg_bool('is_for_sale') }}         as is_for_sale,
    {{ pg_bool('is_kit') }}              as is_kit,
    {{ local_ts('created_at') }}         as created_at_local,
    _loaded_at
from {{ source('erp', 'erp_products') }}
