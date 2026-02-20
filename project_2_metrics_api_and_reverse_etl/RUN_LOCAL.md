# Project 2 Local Completion (shares platform with project_1_cdc_lakehouse_and_dbt_analytics_pipeline)

## Prerequisites

- **Project 1 completed**: Platform has `docker compose up -d`, and has run Silver Merge, Silver registered to REST, Gold (dbt). Trino needs tables: `iceberg.mart_mart.mart_kpis_daily`, `dim_users`, `fct_orders`, `fct_payments`, etc.

## Steps Overview

**All commands execute in project_2_metrics_api_and_reverse_etl root directory** (e.g. `cd "path\to\1.de\project_2_metrics_api_and_reverse_etl"`), host needs access to `localhost:8080` Trino, `localhost:5432` Postgres, `localhost:9092` Kafka.

### 1. Environment

```powershell
cd "C:\Users\qwert\OneDrive\Desktop\Spring 2026\4.Projects\1.de\project_2_metrics_api_and_reverse_etl"
Copy-Item env.example .env
# Confirm TRINO_SCHEMA=mart_mart in .env
```

### 2. customer_segments table (Reverse ETL target)

If `setup.ps1` was not run in project_1_cdc_lakehouse_and_dbt_analytics_pipeline, need to create table first:

```powershell
Get-Content ..\project_1_cdc_lakehouse_and_dbt_analytics_pipeline\platform\local\sql\02-customer_segments.sql | docker exec -i postgres psql -U postgres -d project1
```

### 3. dbt (read P1 Gold, build P2 semantic layer)

If pip installed to user directory, `dbt` is in `%APPDATA%\Python\Python313\Scripts`. Windows needs UTF-8 encoding:

```powershell
cd analytics/dbt
pip install dbt-trino   # If not installed
$env:PYTHONUTF8 = "1"   # Windows encoding fix (Python 3.7+)
$dbt = "$env:APPDATA\Python\Python313\Scripts\dbt.exe"
if (-not (Test-Path $dbt)) { $dbt = "dbt" }   # If already in PATH
& $dbt deps --profiles-dir . --project-dir .
& $dbt run --profiles-dir . --project-dir .
& $dbt test --profiles-dir . --project-dir .
```

### 4. Metrics API

```powershell
cd services/metrics_api
pip install -r requirements.txt
$env:TRINO_HOST="localhost"; $env:TRINO_PORT="8080"
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Verify: Browser or `curl http://localhost:8000/health`, `curl "http://localhost:8000/kpi?date=2026-01-15&version=v1"`.

### 5. Reverse ETL

```powershell
cd reverse_etl
pip install -r requirements.txt
$env:POSTGRES_HOST="localhost"; $env:POSTGRES_PASSWORD="postgres"
python postgres/upsert_segments.py
# or
python kafka/publish_segments.py
```

### 6. Airflow DAG

After running `.\setup.ps1` in project_1_cdc_lakehouse_and_dbt_analytics_pipeline, P2 DAGs are aggregated to `project_1_cdc_lakehouse_and_dbt_analytics_pipeline/platform/local/airflow-dags/`. Open http://localhost:8081, trigger DAG `metric_publish_gate` (need Airflow to access Trino/Postgres/Kafka).

---

For more detailed port and variable descriptions, see **project_1_cdc_lakehouse_and_dbt_analytics_pipeline/platform/local/README.md** "Project 2 connection" and "Project 2 completion steps".
