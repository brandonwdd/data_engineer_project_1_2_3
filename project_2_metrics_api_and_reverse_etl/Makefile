.PHONY: help dbt-run dbt-test dbt-deps api-start api-test reverse-etl-postgres reverse-etl-kafka demo-release demo-reverse-etl demo-api-latency

help:
	@echo "Project 2: Metrics Service + Reverse ETL"
	@echo ""
	@echo "Available targets:"
	@echo "  dbt-deps          - Install dbt dependencies"
	@echo "  dbt-run           - Run dbt models"
	@echo "  dbt-test          - Run dbt tests"
	@echo "  api-start         - Start Metrics API server"
	@echo "  api-test          - Test API endpoints"
	@echo "  reverse-etl-postgres - Run Postgres Reverse ETL"
	@echo "  reverse-etl-kafka    - Run Kafka Reverse ETL"
	@echo "  demo-release      - Run metric release demo"
	@echo "  demo-reverse-etl   - Run Reverse ETL demo"
	@echo "  demo-api-latency   - Run API latency test"

# dbt commands
dbt-deps:
	cd analytics/dbt && dbt deps

dbt-run:
	cd analytics/dbt && dbt run --profiles-dir . --project-dir .

dbt-test:
	cd analytics/dbt && dbt test --profiles-dir . --project-dir .

# API commands
api-start:
	cd services/metrics_api && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

api-test:
	@echo "Testing API endpoints..."
	@curl -s http://localhost:8000/health | jq .
	@curl -s "http://localhost:8000/kpi?date=$(date +%Y-%m-%d)&version=v1" | jq .
	@curl -s "http://localhost:8000/versions" | jq .

# Reverse ETL commands
reverse-etl-postgres:
	cd reverse_etl && python postgres/upsert_segments.py

reverse-etl-kafka:
	cd reverse_etl && python kafka/publish_segments.py

# Demo scripts
demo-release:
	./scripts/demo_metric_release.sh

demo-reverse-etl:
	./scripts/demo_reverse_etl.sh

demo-api-latency:
	./scripts/demo_api_latency.sh
