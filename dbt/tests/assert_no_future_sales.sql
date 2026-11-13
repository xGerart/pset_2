-- Validez: ninguna venta con fecha posterior a hoy (hora del negocio).
select voucher_id, created_at_local
from {{ ref('int_vouchers') }}
where created_at_local > convert_timezone('{{ var("business_tz") }}', current_timestamp())::timestamp_ntz
