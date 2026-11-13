-- D-Q8 La API devuelve dos feriados con la misma fecha (2026-11-02) y omite el 2026-11-03.
-- Se consolida por fecha y se aplican las correcciones justificadas del seed holiday_overrides.
with api as (
    select holiday_date, listagg(distinct local_name, ' / ') within group (order by local_name) as holiday_name
    from {{ ref('stg_nager__holidays') }}
    where is_global
    group by holiday_date
),
overrides as (
    select holiday_date, local_name, action from {{ ref('holiday_overrides') }}
)
select holiday_date, holiday_name, 'api' as holiday_source
from api
where holiday_date not in (select holiday_date from overrides where action = 'remove')
union all
select holiday_date, local_name, 'override'
from overrides
where action = 'add'
  and holiday_date not in (select holiday_date from api)
