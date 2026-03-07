# Project 3 one-command completion — Quality Gate
# Prerequisites: Platform started with project_1_cdc_lakehouse_and_dbt_analytics_pipeline/setup.ps1, and project_2_metrics_api_and_reverse_etl completed (dbt + Metrics + optional Reverse ETL)
# This script: Sync P3 DAG to platform, optional local contract validation, open Airflow and prompt to trigger quality_gate_enforcement

$ErrorActionPreference = "Stop"

$ProjectRoot = $PSScriptRoot
$ParentRepo = Split-Path $ProjectRoot -Parent
$P1Root = Join-Path $ParentRepo "project_1_cdc_lakehouse_and_dbt_analytics_pipeline"
$P1Dags = Join-Path $P1Root "platform\local\airflow-dags"
$P3DagsSource = Join-Path $ProjectRoot "orchestration\airflow\dags"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Project 3 — Quality Gate Completion" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# [1/4] Sync P3 DAG to platform (shares Airflow with P1)
Write-Host "[1/4] Syncing P3 DAG to project_1_cdc_lakehouse_and_dbt_analytics_pipeline/platform/local/airflow-dags..." -ForegroundColor Yellow
if (-not (Test-Path $P1Dags)) {
    New-Item -ItemType Directory -Path $P1Dags -Force | Out-Null
}
if (Test-Path $P3DagsSource) {
    Get-ChildItem -Path $P3DagsSource -Filter "*.py" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName -Destination $P1Dags -Force
        Write-Host "  [OK] $($_.Name)" -ForegroundColor Gray
    }
    Write-Host "[OK] P3 DAG synced" -ForegroundColor Green
} else {
    Write-Host "  Skipping: $P3DagsSource not found" -ForegroundColor Gray
}
Write-Host ""

# [2/4] Optional: Local contract validation
Write-Host "[2/4] Local contract validation (optional)..." -ForegroundColor Yellow
$ValidatorDir = Join-Path $ProjectRoot "tools\contract_validator"
$ContractsDir = Join-Path $ProjectRoot "contracts"
if ((Test-Path (Join-Path $ValidatorDir "contract_validator.py")) -and (Test-Path $ContractsDir)) {
    Push-Location $ValidatorDir
    try {
        python -c "import yaml" 2>$null
        if ($LASTEXITCODE -ne 0) {
            pip install -r requirements.txt -q 2>$null
        }
        python contract_validator.py --contracts-dir $ContractsDir 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Contract validation passed" -ForegroundColor Green
        } else {
            Write-Host "  Contract validation has warnings or failures (see above), continuing DAG execution unaffected" -ForegroundColor Gray
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  Skipping: contract_validator or contracts directory not found" -ForegroundColor Gray
}
Write-Host ""

# [3/4] Check platform and Airflow
Write-Host "[3/4] Checking if platform is running..." -ForegroundColor Yellow
$ComposeDir = Join-Path $P1Root "platform\local"
if (Test-Path (Join-Path $ComposeDir "docker-compose.yml")) {
    Push-Location $ComposeDir
    docker compose ps 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Docker Compose not running in $ComposeDir. Please execute first: cd project_1; .\setup.ps1" -ForegroundColor Red
        exit 1
    }
    Pop-Location
    Write-Host "[OK] Platform running" -ForegroundColor Green
} else {
    Write-Host "project_1_cdc_lakehouse_and_dbt_analytics_pipeline/platform/local not found, please complete project_1_cdc_lakehouse_and_dbt_analytics_pipeline first" -ForegroundColor Red
    exit 1
}
Write-Host ""

# [4/4] Open Airflow and instructions
Write-Host "[4/4] Opening Airflow UI..." -ForegroundColor Yellow
$AirflowUrl = "http://localhost:8081"
Start-Process $AirflowUrl
Write-Host "[OK] Opened $AirflowUrl" -ForegroundColor Green
Write-Host ""
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host " Steps to complete Project 3:" -ForegroundColor Cyan
Write-Host " 1. Find DAG in Airflow: quality_gate_enforcement" -ForegroundColor White
Write-Host " 2. If DAG is paused, click switch to unpause first" -ForegroundColor White
Write-Host " 3. Click DAG name to enter, then click 'Trigger DAG' to manually trigger once" -ForegroundColor White
Write-Host " 4. Check Task status: validate_contracts / run_dbt_tests_* may be skipped (when P3/P1 dbt not mounted); custom_checks and completeness will run Trino (schema: mart_mart)" -ForegroundColor White
Write-Host " 5. After all pass or skipped, enforce_gate_decision will pass, completion achieved" -ForegroundColor White
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host ""
Write-Host "Detailed instructions see project_3_data_contracts_and_quality_gates/README.md 'How to complete Project 3'" -ForegroundColor Gray
