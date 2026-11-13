select
    {{ dbt_utils.generate_surrogate_key(['product_id']) }}   as product_key,
    product_id,
    product_name,
    category_name,
    product_type,
    unit_type,
    sale_price,
    is_kit,
    is_active
from {{ ref('int_products') }}
union all
select '-1', -1, 'Desconocido', 'Sin categoría', null, null, null, false, false
