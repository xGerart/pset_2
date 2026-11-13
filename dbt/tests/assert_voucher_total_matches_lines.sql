{{ config(severity='warn') }}
-- Consistencia: el subtotal del comprobante debe ser la suma de sus líneas. Es warn porque hay
-- casos conocidos (cuantificados en docs/calidad_datos.md); el análisis usa las líneas.
select voucher_id, subtotal, lines_subtotal
from {{ ref('int_vouchers') }}
where is_completed and is_subtotal_mismatch
