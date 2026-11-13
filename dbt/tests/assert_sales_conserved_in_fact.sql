-- Conservación: el hecho tiene exactamente las líneas de los comprobantes completados
-- (ni joins que dupliquen, ni líneas perdidas por una dimensión faltante).
with expected as (
    select count(*) as n, sum(i.subtotal) as amount
    from {{ ref('int_voucher_items') }} i
    join {{ ref('int_vouchers') }} v on v.voucher_id = i.voucher_id and v.is_completed
),
actual as (
    select count(*) as n, sum(net_amount) as amount from {{ ref('fct_sales_lines') }}
)
select * from expected, actual
where expected.n != actual.n or abs(expected.amount - actual.amount) > 0.01
