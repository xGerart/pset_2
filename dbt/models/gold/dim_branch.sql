select
    {{ dbt_utils.generate_surrogate_key(['branch_id']) }}           as branch_key,
    branch_id,
    branch_name,
    branch_type,
    branch_id = {{ var('matriz_branch_id') }}                      as is_matriz,
    case branch_id
        when {{ var('matriz_branch_id') }} then 'tratamiento'
        when {{ var('control_branch_id') }} then 'control'
        else 'excluida'
    end                                                            as experiment_role,
    is_active
from {{ ref('int_branches') }}
union all
select '-1', -1, 'Desconocida', 'UNKNOWN', false, 'excluida', false
