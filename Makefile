# Atajos del pipeline. Requiere .env (copiar de .env.example) y las llaves en secrets/.
include .env
export

KESTRA   := http://localhost:8080/api/v1/main
CURL     := curl -sS --fail-with-body -u "$(KESTRA_USER):$(KESTRA_PASSWORD)"
RUNNER   := docker run --rm --env-file .env.runtime -v $(PWD)/dbt:/app/dbt -v $(PWD)/ingest:/app/ingest -v $(PWD)/secrets:/app/secrets:ro pset2-runner:1.0

.PHONY: secrets build up down deploy ingest backfill transform dbt-build status logs

## Genera .env.kestra (SECRET_* en base64 para Kestra) y .env.runtime (para correr a mano).
secrets:
	@test -f "$(SNOWFLAKE_PRIVATE_KEY_FILE)" || (echo "Falta $(SNOWFLAKE_PRIVATE_KEY_FILE)"; exit 1)
	@test -f "$(ERP_SSH_KEY_FILE)" || (echo "Falta $(ERP_SSH_KEY_FILE)"; exit 1)
	@ssh-keyscan -t ed25519 $(ERP_SSH_HOST) 2>/dev/null > secrets/known_hosts
	@python3 scripts/make_secrets.py
	@echo "OK: .env.kestra y .env.runtime generados (no se versionan)."

build:
	docker compose --profile build build

up:
	docker compose up -d
	@echo "Kestra: http://localhost:8080  ·  Spark master: http://localhost:8081"

down:
	docker compose down

## Publica (crea o actualiza) los flujos de kestra/flows en Kestra.
deploy:
	@for f in kestra/flows/*.yml; do \
	  echo "→ $$f"; \
	  $(CURL) -X POST "$(KESTRA)/flows/validate" -H "Content-Type: application/x-yaml" --data-binary "@$$f" \
	    | python3 -c "import json,sys; e=[x['constraints'] for x in json.load(sys.stdin) if x.get('constraints')]; print(*e, sep='\\n'); sys.exit(1 if e else 0)" || exit 1; \
	  $(CURL) -X POST "$(KESTRA)/flows/import" -F "fileUpload=@$$f" >/dev/null || exit 1; \
	done

## Corrida diaria manual (ventana de reproceso de 7 días).
ingest:
	@$(CURL) -X POST "$(KESTRA)/executions/pset2/ingest_erp" | python3 -m json.tool | grep '"id"' | head -1

## Backfill histórico completo en una sola ejecución.
backfill:
	@$(CURL) -X POST "$(KESTRA)/executions/pset2/ingest_erp" \
	  -F start_date=$(ANALYSIS_START_DATE) -F end_date=$(ANALYSIS_END_DATE) | python3 -m json.tool | grep '"id"' | head -1

transform:
	@$(CURL) -X POST "$(KESTRA)/executions/pset2/transform" | python3 -m json.tool | grep '"id"' | head -1

## dbt fuera de Kestra (desarrollo).
dbt-build:
	$(RUNNER) sh -c 'export SNOWFLAKE_PRIVATE_KEY="$$(cat /app/secrets/snowflake_rsa_key.p8)"; cd /app/dbt && dbt deps && dbt build'

status:
	@$(CURL) "$(KESTRA)/executions/search?namespace=pset2&size=10" | python3 scripts/print_executions.py
