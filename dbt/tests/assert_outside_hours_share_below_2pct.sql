-- Validez: las ventas fuera del horario declarado (después de la gracia de cierre) deben ser
-- menos del 2 % por sucursal. Más que eso significa que el seed de horarios está mal, no los datos.
select branch_id,
       count_if(is_outside_opening_hours)                    as n_outside,
       count(*)                                              as n_sales,
       count_if(is_outside_opening_hours) / count(*)         as outside_share
from {{ ref('int_vouchers') }}
where is_completed
  and is_in_analysis_window
  and branch_id in ({{ var('matriz_branch_id') }}, {{ var('control_branch_id') }})
group by branch_id
having count_if(is_outside_opening_hours) / count(*) >= 0.02
