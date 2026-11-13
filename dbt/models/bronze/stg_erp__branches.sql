select
    try_to_number(id)                               as branch_id,
    name                                            as branch_name,
    branch_type,
    {{ pg_bool('is_active') }}                      as is_active,
    try_to_time(horario_lunes_viernes_inicio)       as erp_weekday_open,
    try_to_time(horario_lunes_viernes_fin)          as erp_weekday_close,
    try_to_time(horario_sabado_inicio)              as erp_saturday_open,
    try_to_time(horario_sabado_fin)                 as erp_saturday_close,
    try_to_time(horario_domingo_inicio)             as erp_sunday_open,
    try_to_time(horario_domingo_fin)                as erp_sunday_close,
    _loaded_at
from {{ source('erp', 'erp_branches') }}
