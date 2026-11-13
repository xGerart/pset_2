{#- Timestamp UTC (texto ISO con zona) -> hora local del negocio, sin zona. -#}
{% macro local_ts(column) -%}
    convert_timezone('{{ var("business_tz") }}', try_to_timestamp_tz({{ column }}))::timestamp_ntz
{%- endmacro %}

{#- Valor booleano exportado por Postgres ('t'/'f'). -#}
{% macro pg_bool(column) -%}
    case {{ column }} when 't' then true when 'f' then false end
{%- endmacro %}
