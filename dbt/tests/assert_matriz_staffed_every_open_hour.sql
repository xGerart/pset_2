-- Regla de negocio: dentro de la ventana de análisis, toda hora abierta de la matriz
-- tiene al menos un vendedor según la regla de turnos. Si falla, el seed de turnos no
-- cubre el horario de apertura y la carga por persona sería indefinida.
select sh.*
from {{ ref('int_store_hours') }} sh
where sh.branch_id = {{ var('matriz_branch_id') }}
  and sh.hour_date between '{{ var("analysis_start_date") }}' and '{{ var("analysis_end_date") }}'
  and coalesce(sh.staff_present, 0) < 1
