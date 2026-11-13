{#- Usa el esquema configurado (BRONZE/SILVER/GOLD) tal cual, sin el prefijo
    del esquema del target que dbt agrega por defecto. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}{{ target.schema }}{%- else -%}{{ custom_schema_name | trim | upper }}{%- endif -%}
{%- endmacro %}
