-- Completitud: todo comprobante completado tiene al menos una línea.
select voucher_id
from {{ ref('int_vouchers') }}
where is_completed and coalesce(line_count, 0) = 0
