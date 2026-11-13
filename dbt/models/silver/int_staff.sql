-- Personal pseudonimizado: el id interno se reemplaza en Gold por un código (P01, P02, ...).
select * exclude (_loaded_at)
from {{ ref('stg_erp__staff') }}
qualify row_number() over (partition by staff_id order by _loaded_at desc) = 1
