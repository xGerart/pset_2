-- Hecho de instantánea periódica (factless + capacidad). GRANO: una fila por sucursal x fecha x hora ABIERTA.
-- Conformado con dim_date, dim_hour y dim_branch; es el spine de la OBT.
select
    sh.store_hour_id                                   as store_hour_key,
    to_number(to_char(sh.hour_date, 'YYYYMMDD'))       as date_key,
    sh.hour_of_day                                     as hour_key,
    b.branch_key,
    sh.is_last_open_hour,
    sh.staff_present                                   -- solo la matriz; NULL en la sucursal de control
from {{ ref('int_store_hours') }} sh
join {{ ref('dim_branch') }} b on b.branch_id = sh.branch_id
