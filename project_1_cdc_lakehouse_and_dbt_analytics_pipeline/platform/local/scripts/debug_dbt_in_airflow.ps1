# Reproduce run_dbt_tests environment in Airflow container and execute dbt, for troubleshooting up_for_retry issues
# Usage: Execute .\scripts\debug_dbt_in_airflow.ps1 in project_1_cdc_lakehouse_and_dbt_analytics_pipeline\platform\local

$ErrorActionPreference = "Stop"
Write-Host "=== 1. Check dbt mount directory ===" -ForegroundColor Cyan
docker exec airflow-scheduler ls -la /opt/airflow/dbt 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed: /opt/airflow/dbt does not exist or is not readable. Please confirm docker compose is run from platform/local and project_2_metrics_api_and_reverse_etl path is correct." -ForegroundColor Red
    exit 1
}

Write-Host "`n=== 2. Environment variables (consistent with DAG) ===" -ForegroundColor Cyan
docker exec airflow-scheduler env | Select-String -Pattern "DBT_|TRINO_" 2>&1

Write-Host "`n=== 3. Execute dbt deps + dbt run + dbt test in container (consistent with DAG) ===" -ForegroundColor Cyan
$dbtCmd = "cd /opt/airflow/dbt && dbt deps --project-dir /opt/airflow/dbt && dbt run --project-dir /opt/airflow/dbt && dbt test --project-dir /opt/airflow/dbt"
docker exec -e DBT_PROJECT_DIR=/opt/airflow/dbt `
  -e TRINO_HOST=trino `
  -e TRINO_PORT=8080 `
  -e TRINO_USER=admin `
  -e TRINO_CATALOG=iceberg `
  -e TRINO_SCHEMA=mart_mart `
  airflow-scheduler bash -c $dbtCmd 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nAll passed (dbt run created tables, dbt test passed)." -ForegroundColor Green
} else {
    Write-Host "`nIf dbt run reports errors: Check if P1 tables exist in Trino: iceberg.mart_mart.fct_orders, dim_users, fct_payments, mart_kpis_daily (need to complete project_1 Silver + Gold first)." -ForegroundColor Yellow
}
