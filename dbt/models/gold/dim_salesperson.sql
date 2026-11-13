-- Vendedores pseudonimizados: el código (P01, P02, ...) sigue el orden de la primera venta.
with first_sale as (
    select salesperson_id, min(created_at_local) as first_sale_at, max(created_at_local) as last_sale_at
    from {{ ref('int_vouchers') }}
    where is_completed
    group by salesperson_id
)
select
    {{ dbt_utils.generate_surrogate_key(['s.staff_id']) }}                       as salesperson_key,
    'P' || lpad(row_number() over (order by f.first_sale_at, s.staff_id), 2, '0') as salesperson_code,
    case
        when s.roles ilike '%ADMIN%' then 'administración'
        when s.roles ilike '%VENDEDOR%' then 'vendedor'
        else 'otro'
    end                                                                          as staff_role,
    f.first_sale_at::date                                                        as first_sale_date,
    f.last_sale_at::date                                                         as last_sale_date,
    s.is_active
from {{ ref('int_staff') }} s
join first_sale f on f.salesperson_id = s.staff_id
union all
select '-1', 'P00', 'desconocido', null, null, false
