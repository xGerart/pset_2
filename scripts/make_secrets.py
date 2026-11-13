"""Genera .env.kestra (SECRET_<NOMBRE>=base64) y .env.runtime (valores planos) desde .env.

Kestra OSS lee secretos de variables de entorno SECRET_* codificadas en base64.
Ninguno de los dos archivos se versiona (.gitignore).
"""
import base64
import os
from pathlib import Path

env = {k: v for k, v in os.environ.items()}
values = {
    "SNOWFLAKE_ACCOUNT": env["SNOWFLAKE_ACCOUNT"],
    "SNOWFLAKE_USER": env["SNOWFLAKE_USER"],
    "SNOWFLAKE_ROLE": env["SNOWFLAKE_ROLE"],
    "SNOWFLAKE_WAREHOUSE": env["SNOWFLAKE_WAREHOUSE"],
    "SNOWFLAKE_DATABASE": env["SNOWFLAKE_DATABASE"],
    "SNOWFLAKE_PRIVATE_KEY": Path(env["SNOWFLAKE_PRIVATE_KEY_FILE"]).read_text(),
    "ERP_SSH_HOST": env["ERP_SSH_HOST"],
    "ERP_SSH_USER": env["ERP_SSH_USER"],
    "ERP_SSH_KEY": Path(env["ERP_SSH_KEY_FILE"]).read_text(),
    "ERP_SSH_KNOWN_HOSTS": Path("secrets/known_hosts").read_text(),
}
with open(".env.kestra", "w") as f:
    for k, v in values.items():
        f.write(f"SECRET_{k}={base64.b64encode(v.encode()).decode()}\n")
# docker --env-file no admite valores multilínea: las llaves viajan en una línea con \n escapado
# y se usan solo para correr dbt/ingesta a mano fuera de Kestra.
with open(".env.runtime", "w") as f:
    for k, v in values.items():
        f.write(f"{k}={v.strip()}\n" if "\n" not in v.strip() else "")
    f.write("SNOWFLAKE_PRIVATE_KEY_FILE=/app/secrets/snowflake_rsa_key.p8\nDBT_PROFILES_DIR=/app/dbt\n")
