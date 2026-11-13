-- Última foto del catálogo + categoría.
with p as (
    select * from {{ ref('stg_erp__products') }}
    qualify row_number() over (partition by product_id order by _loaded_at desc) = 1
),
c as (
    select * from {{ ref('stg_erp__categories') }}
    qualify row_number() over (partition by category_id order by _loaded_at desc) = 1
)
select
    p.product_id,
    p.product_name,
    p.category_id,
    coalesce(c.category_name, 'Sin categoría') as category_name,
    p.brand_id,
    p.product_type,
    p.unit_type,
    p.sale_price,
    p.is_active,
    p.is_for_sale,
    p.is_kit
from p
left join c on c.category_id = p.category_id
