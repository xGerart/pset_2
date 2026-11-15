#!/usr/bin/env bash
# Extractor de solo lectura para el PSet 2. Se instala en el servidor del ERP y
# se ata a la llave SSH de Kestra como "forced command" en authorized_keys:
#
#   command="/home/ubuntu/pset2/pset2_extract.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA... pset2-kestra-extract
#
# Así la llave NO abre una shell: solo puede ejecutar este script, y el script
# solo acepta "<entidad> [fecha_inicio fecha_fin]" y devuelve CSV por stdout.
# Las consultas excluyen datos personales de clientes (nombre, documento,
# correo, teléfono, dirección) y de empleados (nombres).
set -euo pipefail

# Los identificadores del servidor (esquema del tenant, contenedor, base y usuario) no se
# versionan: viven en ~/pset2/extract.env, solo en el servidor. Ver extract.env.example.
CONFIG="$(dirname "$0")/extract.env"
[[ -r "$CONFIG" ]] || { echo "falta $CONFIG" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONFIG"
: "${PG_SCHEMA:?}" "${PG_CONTAINER:?}" "${PG_USER:?}" "${PG_DATABASE:?}"
SCHEMA="$PG_SCHEMA"
PSQL=(docker exec -i "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DATABASE" -v ON_ERROR_STOP=1 -q -At)

read -r ENTITY START END EXTRA <<<"${SSH_ORIGINAL_COMMAND:-}"
DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

need_window() {
  [[ "${START:-}" =~ $DATE_RE && "${END:-}" =~ $DATE_RE && -z "${EXTRA:-}" ]] \
    || { echo "uso: $ENTITY AAAA-MM-DD AAAA-MM-DD" >&2; exit 64; }
}

# Ventana por fecha LOCAL de creación del comprobante, [START, END] inclusive.
WINDOW="(v.created_at AT TIME ZONE 'America/Guayaquil')::date BETWEEN DATE '${START:-1900-01-01}' AND DATE '${END:-1900-01-01}'"

case "$ENTITY" in
  vouchers)
    need_window
    SQL="SELECT v.id, v.branch_id, v.status, v.created_at, v.processed_at, v.cancelled_at,
                v.salesperson_id, v.processed_by_id, v.created_by_id,
                v.customer_document_type, (v.customer_id IS NOT NULL) AS has_customer_id,
                v.subtotal, v.discount, v.total, v.shipping_amount,
                v.requires_comprobante, (v.coupon_code IS NOT NULL) AS has_coupon
         FROM $SCHEMA.sales_vouchers v WHERE $WINDOW ORDER BY v.id" ;;
  voucher_items)
    need_window
    SQL="SELECT i.id, i.voucher_id, i.product_id, i.sku_id, i.conversion_factor, i.quantity,
                i.base_units, i.free_units, i.unit_price, i.unit_price_original, i.discount,
                i.subtotal, i.returned_quantity, i.created_at
         FROM $SCHEMA.sales_voucher_items i JOIN $SCHEMA.sales_vouchers v ON v.id = i.voucher_id
         WHERE $WINDOW ORDER BY i.id" ;;
  batch_consumption)
    need_window
    SQL="SELECT c.id, c.voucher_id, c.product_id, c.branch_id, c.batch_id, c.quantity,
                c.unit_cost, c.returned_quantity, c.created_at
         FROM $SCHEMA.inventory_salebatchconsumption c JOIN $SCHEMA.sales_vouchers v ON v.id = c.voucher_id
         WHERE $WINDOW ORDER BY c.id" ;;
  branches)
    SQL="SELECT id, name, branch_type, is_active,
                horario_lunes_viernes_inicio, horario_lunes_viernes_fin,
                horario_sabado_inicio, horario_sabado_fin,
                horario_domingo_inicio, horario_domingo_fin, created_at, updated_at
         FROM $SCHEMA.users_branch ORDER BY id" ;;
  products)
    SQL="SELECT id, name, category_id, brand_id, product_type, unit_type, sale_price,
                is_active, is_for_sale, is_kit, created_at, updated_at
         FROM $SCHEMA.inventory_product ORDER BY id" ;;
  categories)
    SQL="SELECT id, name FROM $SCHEMA.inventory_category ORDER BY id" ;;
  staff)
    # Sin nombres: solo id interno, estado y roles.
    SQL="SELECT u.id, u.is_active,
                (SELECT string_agg(r.name, ',' ORDER BY r.name)
                   FROM $SCHEMA.users_user_roles ur JOIN $SCHEMA.users_role r ON r.id = ur.role_id
                  WHERE ur.user_id = u.id) AS roles
         FROM $SCHEMA.users_user u
         WHERE u.id IN (SELECT salesperson_id FROM $SCHEMA.sales_vouchers
                        UNION SELECT processed_by_id FROM $SCHEMA.sales_vouchers)
         ORDER BY u.id" ;;
  *)
    echo "entidad no permitida: '${ENTITY:-}'" >&2; exit 64 ;;
esac

# \copy exige el SQL en una sola línea.
SQL="$(tr -s '\n ' '  ' <<<"$SQL")"

# Transacción de solo lectura: aunque alguien alterara el SQL, Postgres rechaza escrituras.
"${PSQL[@]}" <<EOF
BEGIN TRANSACTION READ ONLY;
\copy ($SQL) TO STDOUT WITH (FORMAT csv, HEADER true)
COMMIT;
EOF
