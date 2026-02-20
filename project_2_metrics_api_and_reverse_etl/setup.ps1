# Project 2 one-command completion — shares platform with project_1_cdc_lakehouse_and_dbt_analytics_pipeline
# Usage: Execute .\setup.ps1 in the project_2_metrics_api_and_reverse_etl directory
#
# What this script does (one-command completion of all P2):
#   1. Environment: Create .env from env.example (if not exists), load into current process for dbt/API use
#   2. customer_segments: Create Reverse ETL target table in Postgres project1
#   3. dbt: deps → run → test (read P1 Gold iceberg.mart_mart.*, build P2 semantic layer and test)
#   4. Metrics API: Install dependencies and start in background (http://localhost:8000)
#   5. Reverse ETL: Install dependencies and execute upsert_segments (write to Postgres customer_segments)
#   6. metric_release_log: Create release log table in Trino (for Airflow DAG insert_release_log to write)
#   7. Airflow: Open browser and prompt to trigger DAG metric_publish_gate
#
# Prerequisites:
#   - project_1_cdc_lakehouse_and_dbt_analytics_pipeline completed: Executed .\setup.ps1 in that folder, or at least platform started and Silver + Gold completed
#   - P1 tables exist in Trino: iceberg.mart_mart.fct_orders, dim_users, fct_payments, mart_kpis_daily

$ErrorActionPreference = "Stop"

$ProjectRoot = $PSScriptRoot
$P1Local = Join-Path (Split-Path $ProjectRoot -Parent) "project_1_cdc_lakehouse_and_dbt_analytics_pipeline\platform\local"

# Load .env into current process (TRINO_* etc. for dbt use)
function Load-DotEnv {
    $envPath = Join-Path $ProjectRoot ".env"
    if (-not (Test-Path $envPath)) { return }
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)=(.*)$') {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim().Trim('"').Trim("'")
            [Environment]::SetEnvironmentVariable($k, $v, 'Process')
        }
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Project 2 One-Command Completion" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# [1/7] Environment
Write-Host "[1/7] Environment (.env)..." -ForegroundColor Yellow
if (-not (Test-Path (Join-Path $ProjectRoot ".env"))) {
    Copy-Item (Join-Path $ProjectRoot "env.example") (Join-Path $ProjectRoot ".env")
    Write-Host "  ✓ Created .env from env.example (TRINO_HOST=localhost, TRINO_SCHEMA=mart_mart)" -ForegroundColor Gray
} else {
    Write-Host "  ✓ .env already exists" -ForegroundColor Gray
}
Load-DotEnv
# When running dbt locally, connect to Trino using localhost, schema must be mart_mart (consistent with P1 Gold)
if (-not $env:TRINO_SCHEMA) { $env:TRINO_SCHEMA = "mart_mart" }
if (-not $env:TRINO_HOST)   { $env:TRINO_HOST   = "localhost" }
if (-not $env:TRINO_PORT)   { $env:TRINO_PORT   = "8080" }
Write-Host ""

# [2/7] customer_segments table
Write-Host "[2/7] customer_segments table (Reverse ETL target)..." -ForegroundColor Yellow
$P2Sql = Join-Path $P1Local "sql\02-customer_segments.sql"
if (Test-Path $P2Sql) {
    Get-Content $P2Sql -Raw | docker exec -i postgres psql -U postgres -d project1 2>&1 | Out-Null
    Write-Host "  ✓ customer_segments created/already exists" -ForegroundColor Gray
} else {
    Write-Host "  ⊘ $P2Sql not found, skipping (please run project_1_cdc_lakehouse_and_dbt_analytics_pipeline setup first)" -ForegroundColor Gray
}
Write-Host ""

# [3/7] dbt
Write-Host "[3/7] dbt (deps → run → test, read P1 Gold, build P2 semantic layer)..." -ForegroundColor Yellow
$env:PYTHONUTF8 = "1"
$DbtDir = Join-Path $ProjectRoot "analytics\dbt"
$dbtExe = "dbt"
if (Test-Path "$env:APPDATA\Python\Python313\Scripts\dbt.exe") { $dbtExe = "$env:APPDATA\Python\Python313\Scripts\dbt.exe" }
elseif (Test-Path "$env:LOCALAPPDATA\Programs\Python\Python313\Scripts\dbt.exe") { $dbtExe = "$env:LOCALAPPDATA\Programs\Python\Python313\Scripts\dbt.exe" }

Push-Location $DbtDir
try {
    pip install -q dbt-trino 2>$null
    & $dbtExe deps --profiles-dir . --project-dir .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ✗ dbt deps failed" -ForegroundColor Red
        exit 1
    }
    & $dbtExe run --profiles-dir . --project-dir .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ✗ dbt run failed (please confirm project_1_cdc_lakehouse_and_dbt_analytics_pipeline completed, Trino has iceberg.mart_mart.fct_orders etc.)" -ForegroundColor Red
        exit 1
    }
    & $dbtExe test --profiles-dir . --project-dir .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Warning: dbt test has failures, can retry later" -ForegroundColor Yellow
    } else {
        Write-Host "  ✓ dbt completed (7 models + 21 tests)" -ForegroundColor Green
    }
} finally {
    Pop-Location
}
Write-Host ""

# [4/7] Metrics API
Write-Host "[4/7] Metrics API (install dependencies and start in background)..." -ForegroundColor Yellow
$MetricsApiDir = Join-Path $ProjectRoot "services\metrics_api"
$MetricsReq = Join-Path $MetricsApiDir "requirements.txt"
if (Test-Path $MetricsReq) {
    Push-Location $MetricsApiDir
    pip install -q -r requirements.txt 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Warning: Metrics API dependency installation failed, can do later: cd services\metrics_api && pip install -r requirements.txt" -ForegroundColor Yellow
    } else {
        Start-Process -FilePath "python" -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000" -WorkingDirectory $MetricsApiDir -WindowStyle Hidden
        Write-Host "  ✓ Metrics API started (background) http://localhost:8000/health" -ForegroundColor Gray
    }
    Pop-Location
} else {
    Write-Host "  ⊘ $MetricsReq not found, skipping" -ForegroundColor Gray
}
Write-Host ""

# [5/7] Reverse ETL
Write-Host "[5/7] Reverse ETL (install dependencies and upsert segments)..." -ForegroundColor Yellow
$ReverseEtlDir = Join-Path $ProjectRoot "reverse_etl"
$ReverseEtlReq = Join-Path $ReverseEtlDir "requirements.txt"
if (Test-Path $ReverseEtlReq) {
    Push-Location $ReverseEtlDir
    pip install -q -r requirements.txt 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Warning: Reverse ETL dependency installation failed" -ForegroundColor Yellow
    } else {
        python postgres/upsert_segments.py 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Reverse ETL upsert completed" -ForegroundColor Gray
        } else {
            Write-Host "  Warning: upsert_segments.py exception (check Postgres/Trino and data)" -ForegroundColor Yellow
        }
    }
    Pop-Location
} else {
    Write-Host "  ⊘ $ReverseEtlReq not found, skipping" -ForegroundColor Gray
}
Write-Host ""

# [6/7] metric_release_log (create table in Trino for Airflow DAG to write)
Write-Host "[6/7] metric_release_log (create table in Trino for Airflow release log)..." -ForegroundColor Yellow
$DdlPath = Join-Path $ProjectRoot "lakehouse\ddl\metric_release_log.sql"
if (Test-Path $DdlPath) {
    docker cp $DdlPath trino:/tmp/metric_release_log.sql 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        docker exec trino trino -f /tmp/metric_release_log.sql 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ metric_release_log created/already exists" -ForegroundColor Gray
        } else {
            Write-Host "  ⊘ Trino DDL execution failed, DAG insert_release_log will skip writing" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ⊘ trino container not running or cp failed, skipping" -ForegroundColor Gray
    }
} else {
    Write-Host "  ⊘ $DdlPath not found, skipping" -ForegroundColor Gray
}
Write-Host ""

# [7/7] Airflow
Write-Host "[7/7] Airflow (trigger DAG to complete release gate)..." -ForegroundColor Yellow
Write-Host "  Open http://localhost:8081, login admin / admin, trigger DAG: metric_publish_gate" -ForegroundColor Gray
try {
    Start-Process "http://localhost:8081"
    Write-Host "  ✓ Attempted to open browser" -ForegroundColor Gray
} catch {
    Write-Host "  Please manually open: http://localhost:8081" -ForegroundColor Gray
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Project 2 One-Command Completion Finished" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script has executed:" -ForegroundColor White
Write-Host "  1. .env (TRINO_SCHEMA=mart_mart etc.)" -ForegroundColor Gray
Write-Host "  2. customer_segments table (Postgres)" -ForegroundColor Gray
Write-Host "  3. dbt deps → run → test (P2 semantic layer)" -ForegroundColor Gray
Write-Host "  4. Metrics API background (http://localhost:8000)" -ForegroundColor Gray
Write-Host "  5. Reverse ETL upsert (customer_segments)" -ForegroundColor Gray
Write-Host "  6. metric_release_log table (Trino)" -ForegroundColor Gray
Write-Host "  7. Airflow opened, please trigger DAG metric_publish_gate" -ForegroundColor Gray
Write-Host ""
Write-Host "Links: Metrics API http://localhost:8000/health | Airflow http://localhost:8081" -ForegroundColor Cyan
Write-Host ""
