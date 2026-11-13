select
    try_to_number(id)    as category_id,
    name                 as category_name,
    _loaded_at
from {{ source('erp', 'erp_categories') }}
