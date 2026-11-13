select * exclude (_loaded_at)
from {{ ref('stg_erp__branches') }}
qualify row_number() over (partition by branch_id order by _loaded_at desc) = 1
