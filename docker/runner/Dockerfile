# Imagen de trabajo para las tareas de Kestra: extracción (ssh), carga a
# Snowflake (conector Python) y transformaciones (dbt-snowflake).
FROM python:3.12.12-slim-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-client git \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

WORKDIR /app
