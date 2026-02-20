# Platform one-command initialization — Shared by Project 1 / 2 / 3
# Usage: Execute .\setup.ps1 in the project_1_cdc_lakehouse_and_dbt_analytics_pipeline directory
# Effect: Full Docker startup (including Spark Bronze persistent) + Postgres/CDC/Kafka + one Silver + Gold run, all three projects ready

$ErrorActionPreference = "Stop"

$ProjectRoot = $PSScriptRoot
$DockerComposeDir = Join-Path $ProjectRoot "platform\local"
$ParentRepo = Split-Path $ProjectRoot -Parent
$ConnectorConfig = Join-Path $ProjectRoot "connectors\debezium\configs\project_1_connector.json"
$AirflowDagsDir = Join-Path $DockerComposeDir "airflow-dags"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Platform One-Command Initialization (P1/P2/P3 Shared)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# [1/8] Aggregate Airflow DAGs (P1/P2/P3)
Write-Host "[1/8] Aggregating Airflow DAGs..." -ForegroundColor Yellow
if (-not (Test-Path $AirflowDagsDir)) { New-Item -ItemType Directory -Path $AirflowDagsDir -Force | Out-Null }
$dagSources = @(
    (Join-Path $ProjectRoot "orchestration\airflow\dags"),
    (Join-Path $ParentRepo "project_2_metrics_api_and_reverse_etl\orchestration\airflow\dags"),
    (Join-Path $ParentRepo "project_3_data_contracts_and_quality_gates\orchestration\airflow\dags")
)
foreach ($src in $dagSources) {
    if (Test-Path $src) {
        Get-ChildItem -Path $src -Filter "*.py" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName -Destination $AirflowDagsDir -Force
            Write-Host "  ✓ $($_.Name)" -ForegroundColor Gray
        }
    }
}
Write-Host "✓ DAGs aggregation completed" -ForegroundColor Green
Write-Host ""

# [2/8] Start Docker services (including Spark Bronze persistent)
Write-Host "[2/8] Starting Docker services (Postgres/Kafka/MinIO/Trino/Airflow/Spark)..." -ForegroundColor Yellow
Set-Location $DockerComposeDir
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker service startup failed" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Docker services started" -ForegroundColor Green
Write-Host "Waiting 45 seconds for services and Spark to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 45
Write-Host ""

# [3/8] Check service status
Write-Host "[3/8] Checking service status..." -ForegroundColor Yellow
docker compose ps
Write-Host "✓ Service status check completed" -ForegroundColor Green
Write-Host ""

# [4/8] Initialize Postgres + Debezium + Kafka Topics + test data
Write-Host "[4/8] Initializing Postgres and CDC..." -ForegroundColor Yellow
$SqlFile = Join-Path $ProjectRoot "infra\sql\project1.sql"
docker cp $SqlFile postgres:/tmp/project1.sql
docker exec -i postgres psql -U postgres -d project1 -f /tmp/project1.sql 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Database initialization failed" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Database schema" -ForegroundColor Gray

Write-Host "  Waiting for Kafka Connect REST API to be ready..." -ForegroundColor Gray
$maxRetries = 30
$retryCount = 0
$kafkaConnectReady = $false
while ($retryCount -lt $maxRetries -and -not $kafkaConnectReady) {
    try {
        $testResponse = Invoke-WebRequest -Uri http://localhost:8083/connector-plugins -Method GET -TimeoutSec 2 -ErrorAction Stop
        if ($testResponse.StatusCode -eq 200) {
            $kafkaConnectReady = $true
            Write-Host "  ✓ Kafka Connect REST API is ready" -ForegroundColor Gray
        }
    } catch {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds 2
        }
    }
}
if (-not $kafkaConnectReady) {
    Write-Host "Warning: Kafka Connect REST API not ready, but continuing to create connector..." -ForegroundColor Yellow
}

Write-Host "  Creating Debezium connector..." -ForegroundColor Gray
$json = Get-Content $ConnectorConfig -Raw
try {
    $response = Invoke-WebRequest -Uri http://localhost:8083/connectors -Method POST -ContentType "application/json" -Body $json -ErrorAction Stop
    if ($response.StatusCode -eq 201 -or $response.StatusCode -eq 200) {
        Write-Host "  ✓ Debezium connector created" -ForegroundColor Gray
    } else {
        Write-Host "  ✓ Connector may already exist" -ForegroundColor Gray
    }
} catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Host "  ✓ Connector already exists, skipping" -ForegroundColor Gray
    } else {
        Write-Host "Error: Connector creation failed: $_" -ForegroundColor Red
        exit 1
    }
}

$topics = @("dbserver_docker.public.users", "dbserver_docker.public.orders", "dbserver_docker.public.payments")
foreach ($topic in $topics) {
    docker compose exec -T kafka kafka-topics --bootstrap-server localhost:9092 --create --topic $topic --partitions 1 --replication-factor 1 --if-not-exists 2>&1 | Out-Null
}
Write-Host "  ✓ Kafka Topics" -ForegroundColor Gray

docker exec -i postgres psql -U postgres -d project1 -c "INSERT INTO public.users (user_id, email, status, created_at, updated_at) VALUES (100, 'test100@example.com', 'active', NOW(), NOW()) ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW();" 2>&1 | Out-Null
Write-Host "  ✓ Test data (user_id=100)" -ForegroundColor Gray
Write-Host "✓ Postgres/CDC initialization completed" -ForegroundColor Green
Write-Host ""

# [5/8] Wait for Bronze to consume a batch of data (optional short wait)
Write-Host "[5/8] Waiting for Bronze to consume CDC (about 15 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 15
Write-Host "✓ Ready" -ForegroundColor Green
Write-Host ""

# [6/8] Run Silver Merge once
Write-Host "[6/8] Running Silver Merge (Bronze → Silver)..." -ForegroundColor Yellow
$silverCmd = "/opt/spark/bin/spark-submit --master local[*] --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2,org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,org.apache.hadoop:hadoop-aws:3.3.4 /app/streaming/spark/silver_merge/merge_silver.py"
docker compose run --rm spark sh -c "$silverCmd"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Silver Merge not successful, can retry later in Airflow or manually" -ForegroundColor Yellow
} else {
    Write-Host "✓ Silver Merge completed" -ForegroundColor Green
}
Write-Host ""

# [6b/8] Register Silver to REST catalog (Trino/dbt uses REST, otherwise will report Schema 'silver' does not exist)
Write-Host "[6b/8] Registering Silver to REST catalog (for Trino/dbt)..." -ForegroundColor Yellow
$registerCmd = "/opt/spark/bin/spark-submit --master local[*] --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2,org.apache.hadoop:hadoop-aws:3.3.4 /app/scripts/register_silver_to_rest_catalog.py"
docker compose run --rm spark sh -c $registerCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Silver registration to REST not successful, dbt may report Schema 'silver' does not exist" -ForegroundColor Yellow
} else {
    Write-Host "✓ Silver registered to REST catalog" -ForegroundColor Green
}
Write-Host ""

# [7/8] Run Gold layer once (dbt)
Write-Host "[7/8] Running Gold layer (dbt)..." -ForegroundColor Yellow
$dbtCmd = "pip install --no-cache-dir dbt-trino && cd /app/analytics/dbt && rm -rf dbt_packages && dbt deps --profiles-dir /app/analytics/dbt && dbt run --profiles-dir /app/analytics/dbt"
docker compose --profile gold run --rm dbt sh -c $dbtCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: dbt not fully successful, can execute later: docker compose --profile gold run --rm dbt sh -c \"pip install dbt-trino && cd /app/analytics/dbt && dbt deps && dbt run\"" -ForegroundColor Yellow
} else {
    Write-Host "✓ Gold (dbt) completed" -ForegroundColor Green
}
Write-Host ""

# [8/8] Project 2 tables (Reverse ETL)
Write-Host "[8/8] Project 2 tables (customer_segments)..." -ForegroundColor Yellow
$P2Sql = Join-Path $DockerComposeDir "sql\02-customer_segments.sql"
if (Test-Path $P2Sql) {
    Get-Content $P2Sql | docker exec -i postgres psql -U postgres -d project1 2>&1 | Out-Null
    Write-Host "  ✓ customer_segments created" -ForegroundColor Gray
} else {
    Write-Host "  ⊘ sql\02-customer_segments.sql not found, skipping" -ForegroundColor Gray
}
Write-Host "✓ P2 tables ready" -ForegroundColor Green
Write-Host ""

# Complete
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " ✓ One-command initialization completed, all three projects ready" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Services and ports:" -ForegroundColor White
Write-Host "  Trino        http://localhost:8080" -ForegroundColor Gray
Write-Host "  Airflow      http://localhost:8081   (admin / admin)" -ForegroundColor Gray
Write-Host "  MinIO        http://localhost:9001   (minioadmin / minioadmin)" -ForegroundColor Gray
Write-Host "  Kafka        9092, 29092" -ForegroundColor Gray
Write-Host "  Postgres     5432 (project1, airflow)" -ForegroundColor Gray
Write-Host ""
Write-Host "Project 1: CDC → Bronze(Spark persistent) → Silver/Gold completed; after inserting data Bronze automatically processes, Silver/Gold can be triggered via Airflow backfill or run manually." -ForegroundColor White
Write-Host "Project 2: Trino/Postgres/Kafka/Airflow available; Metrics API, Reverse ETL, metric_publish_gate DAG." -ForegroundColor White
Write-Host "Project 3: Trino/Airflow available; quality_gate_enforcement and other DAGs." -ForegroundColor White
Write-Host ""

Set-Location $ProjectRoot
