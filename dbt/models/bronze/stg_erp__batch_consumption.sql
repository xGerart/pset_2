select
    try_to_number(id)                    as consumption_id,
    try_to_number(voucher_id)            as voucher_id,
    try_to_number(product_id)            as product_id,
    try_to_number(branch_id)             as branch_id,
    try_to_number(batch_id)              as batch_id,
    try_to_number(quantity)              as quantity,
    try_to_decimal(unit_cost, 12, 4)     as unit_cost,
    try_to_number(returned_quantity)     as returned_quantity,
    {{ local_ts('created_at') }}         as created_at_local,
    _loaded_at,
    _run_id
from {{ source('erp', 'erp_batch_consumption') }}
