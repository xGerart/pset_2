-- Spine: una fila por sucursal x fecha x hora en que la tienda estuvo ABIERTA.
-- Es la base de la OBT: una hora abierta sin ventas existe aquí (con 0), una hora cerrada no existe.
with dates as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="'" ~ var('analysis_start_date') ~ "'::date",
        end_date="'" ~ var('calendar_end_date') ~ "'::date + 1"
    ) }}
),

days as (
    select
        d.date_day::date                                                    as hour_date,
        lower(dayname(d.date_day))                                          as dow,
        h.holiday_date is not null                                          as is_holiday
    from dates d
    left join {{ ref('int_holidays') }} h on h.holiday_date = d.date_day::date
),

regular as (
    select
        o.branch_id,
        days.hour_date,
        days.dow,
        days.is_holiday,
        o.open_hour,
        o.close_hour
    from days
    join {{ ref('opening_hours') }} o
      on o.day_type = days.dow
     and days.hour_date between o.valid_from and o.valid_to
),

with_holiday as (
    select
        r.branch_id,
        r.hour_date,
        r.dow,
        r.is_holiday,
        r.open_hour,
        iff(r.is_holiday, least(r.close_hour, coalesce(hol.close_hour, r.close_hour)), r.close_hour) as close_hour
    from regular r
    left join {{ ref('opening_hours') }} hol
      on hol.branch_id = r.branch_id
     and hol.day_type = 'holiday'
     and r.hour_date between hol.valid_from and hol.valid_to
),

hours as (
    select row_number() over (order by seq4()) - 1 as hour_of_day
    from table(generator(rowcount => 24))
)

select
    {{ dbt_utils.generate_surrogate_key(['w.branch_id', 'w.hour_date', 'h.hour_of_day']) }} as store_hour_id,
    w.branch_id,
    w.hour_date,
    h.hour_of_day,
    w.dow,
    w.is_holiday,
    w.open_hour,
    w.close_hour,
    h.hour_of_day = w.close_hour - 1                                  as is_last_open_hour,
    s.staff_present
from with_holiday w
join hours h
  on h.hour_of_day >= w.open_hour
 and h.hour_of_day <  w.close_hour
left join {{ ref('staffing_rules') }} s
  on s.branch_id = w.branch_id
 and s.day_type = w.dow
 and s.hour = h.hour_of_day
 and w.hour_date between s.valid_from and s.valid_to
