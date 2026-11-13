select
    hour_of_day                                    as hour_key,
    hour_of_day,
    lpad(hour_of_day, 2, '0') || ':00-' || lpad(hour_of_day + 1, 2, '0') || ':00' as hour_label,
    case
        when hour_of_day < 12 then 'mañana'
        when hour_of_day < 15 then 'mediodía'
        else 'tarde'
    end                                            as day_part
from (select row_number() over (order by seq4()) - 1 as hour_of_day from table(generator(rowcount => 24)))
