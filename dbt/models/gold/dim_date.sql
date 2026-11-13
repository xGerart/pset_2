-- Dimensión fecha (conformada): calendario con feriados y eventos estacionales de Ecuador.
with dates as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="'" ~ var('analysis_start_date') ~ "'::date",
        end_date="'" ~ var('calendar_end_date') ~ "'::date + 1"
    ) }}
),
events as (
    select d.date_day::date as event_date,
           listagg(e.event_code, ',') within group (order by e.event_code) as event_codes
    from dates d
    join {{ ref('calendar_events') }} e on d.date_day::date between e.start_date and e.end_date
    group by 1
)
select
    to_number(to_char(d.date_day, 'YYYYMMDD'))     as date_key,
    d.date_day::date                               as calendar_date,
    dayofweekiso(d.date_day)                       as iso_day_of_week,
    lower(dayname(d.date_day))                     as day_name,
    dayofweekiso(d.date_day) in (6, 7)             as is_weekend,
    weekiso(d.date_day)                            as iso_week,
    date_trunc('week', d.date_day)::date           as week_start_date,
    month(d.date_day)                              as month_number,
    day(d.date_day)                                as day_of_month,
    h.holiday_date is not null                     as is_holiday,
    h.holiday_name,
    coalesce(e.event_codes, '')                    as event_codes,
    e.event_codes is not null                      as is_seasonal_event,
    d.date_day::date between '{{ var("analysis_start_date") }}'
                          and '{{ var("analysis_end_date") }}' as is_in_analysis_window
from dates d
left join {{ ref('int_holidays') }} h on h.holiday_date = d.date_day::date
left join events e on e.event_date = d.date_day::date
