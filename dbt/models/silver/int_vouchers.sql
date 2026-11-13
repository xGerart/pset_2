-- Silver: comprobantes limpios. Decisiones (ver docs/calidad_datos.md):
--  D-Q1 Duplicados por la ventana de reproceso -> se conserva la versión más reciente (_loaded_at),
--       porque el estado puede cambiar después (anulación).
--  D-Q4 Ventas registradas hasta N min después del cierre -> se atribuyen a la última hora abierta.
--  Se marcan (no se borran): anulados, procesados antes de creados, total != suma de líneas.
with latest as (
    select *
    from {{ ref('stg_erp__vouchers') }}
    qualify row_number() over (partition by voucher_id order by _loaded_at desc, _run_id desc) = 1
),

line_totals as (
    select voucher_id, sum(subtotal) as lines_subtotal, count(*) as line_count
    from {{ ref('int_voucher_items') }}
    group by voucher_id
),

hours as (
    select * from {{ ref('int_store_hours') }}
),

staff as (
    select staff_id, roles from {{ ref('int_staff') }}
)

select
    v.voucher_id,
    v.branch_id,
    v.voucher_status,
    v.voucher_status = 'completed'                                   as is_completed,
    v.created_at_utc,
    v.created_at_local,
    v.created_at_local::date                                         as sale_date,
    hour(v.created_at_local)                                         as clock_hour,
    -- Hora efectiva: si cae en la hora del cierre dentro de la gracia, va a la última hora abierta.
    case
        when h_clock.store_hour_id is not null then hour(v.created_at_local)
        when h_prev.store_hour_id is not null
             and minute(v.created_at_local) < {{ var('post_close_grace_minutes') }}
            then hour(v.created_at_local) - 1
    end                                                              as effective_hour,
    h_clock.store_hour_id is null and h_prev.store_hour_id is not null
        and minute(v.created_at_local) < {{ var('post_close_grace_minutes') }}
                                                                     as is_post_close_grace,
    h_clock.store_hour_id is null
        and not coalesce(h_prev.store_hour_id is not null
                         and minute(v.created_at_local) < {{ var('post_close_grace_minutes') }}, false)
                                                                     as is_outside_opening_hours,
    v.processed_at_local,
    v.cancelled_at_local,
    v.processed_at_local < v.created_at_local                        as is_processed_before_created,
    v.salesperson_id,
    coalesce(s.roles, '') ilike '%ADMIN%'                            as is_admin_sale,
    v.processed_by_id,
    v.has_customer_id,
    v.customer_document_type,
    v.subtotal,
    v.discount,
    v.total,
    v.shipping_amount,
    lt.lines_subtotal,
    lt.line_count,
    abs(v.subtotal - coalesce(lt.lines_subtotal, 0)) > 0.01          as is_subtotal_mismatch,
    v.created_at_local::date between '{{ var("analysis_start_date") }}'
                              and '{{ var("analysis_end_date") }}'   as is_in_analysis_window,
    v._loaded_at
from latest v
left join line_totals lt on lt.voucher_id = v.voucher_id
left join hours h_clock
    on h_clock.branch_id = v.branch_id
   and h_clock.hour_date = v.created_at_local::date
   and h_clock.hour_of_day = hour(v.created_at_local)
left join hours h_prev
    on h_prev.branch_id = v.branch_id
   and h_prev.hour_date = v.created_at_local::date
   and h_prev.hour_of_day = hour(v.created_at_local) - 1
   and h_prev.is_last_open_hour
left join staff s on s.staff_id = v.salesperson_id
