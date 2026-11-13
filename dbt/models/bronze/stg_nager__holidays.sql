select
    try_to_date("DATE")                  as holiday_date,
    local_name,
    name                                 as holiday_name_en,
    country_code,
    upper(is_global) = 'TRUE'            as is_global,
    types,
    _loaded_at
from {{ source('nager', 'nager_holidays') }}
