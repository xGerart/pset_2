select
    try_to_number(id)              as staff_id,
    {{ pg_bool('is_active') }}     as is_active,
    roles,
    _loaded_at
from {{ source('erp', 'erp_staff') }}
