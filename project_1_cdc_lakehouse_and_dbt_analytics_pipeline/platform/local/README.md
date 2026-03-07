# Platform Local — One Stack for Project 1, 2, 3

One `docker compose up -d` brings up all services used by **Project 1**, **Project 2**, and **Project 3**.

- **Compose project name**: `de_platform` (Docker Desktop "Name" column; network `de_platform_default`)
- **Container names**: no prefix — `postgres`, `kafka`, `trino`, `minio`, `airflow-webserver`, etc.
- **Volume names** (de- prefix): all volumes listed below; no anonymous (hash) volumes.

## Volumes — all required, none optional

**All containers, images, and volumes are required** — the stack will not function correctly if any are removed.

All volumes are shared by the **one stack** used by Project 1, 2, and 3. No volume is project-specific.

| Volume | Purpose | Used by |
|--------|---------|---------|
| **de-pgdata** | Postgres data (DB `project1` + `airflow`) | P1, P2, Airflow |
| **de-kafkadata** | Kafka broker data | P1, P2 |
| **de-miniodata** | MinIO object storage (warehouse, Iceberg) | P1, Trino, P2, P3 |
| **de-zookeeper-data** | Zookeeper data | Kafka (P1, P2) |
| **de-zookeeper-log** | Zookeeper logs | Kafka |
| **de-zookeeper-root** | Zookeeper root dir | Kafka |
| **de-zookeeper-secrets** | Zookeeper secrets dir | Kafka |
| **de-kafka-root** | Kafka root dir | P1, P2 |
| **de-kafka-secrets** | Kafka secrets dir | P1, P2 |
| **de-kafka-connect-root** | Kafka Connect root dir | P1 (Debezium) |
| **de-kafka-connect-data** | Kafka Connect state | P1 (Debezium) |
| **de-kafka-connect-logs** | Kafka Connect logs | P1 (Debezium) |
| **de-kafka-connect-config** | Kafka Connect config dir | P1 (Debezium) |
| **de-iceberg-rest-data** | Iceberg REST catalog metadata | Trino (P2, P3) |
| **de-trino-data** | Trino runtime data | P2, P3 |
| **de-airflow-home** | Airflow home (logs, files) | P2, P3 |
| **de-airflow-db-create** | One-off “create DB” container | Airflow init |
| **de-minio-init-tmp** | MinIO init temp (one-off) | MinIO init |

**Note**: Some volumes (e.g., `*-secrets`, `*-root`) may be empty or small, but they are **required** to prevent Docker from creating anonymous (hash-named) volumes. Removing any volume from the compose file will cause Docker to create an anonymous volume for that path, defeating the purpose of named volumes.

## Quick start (one-command initialization, three projects shared)

Execute in the **project_1_cdc_lakehouse_and_dbt_analytics_pipeline** directory:

```powershell
cd project_1_cdc_lakehouse_and_dbt_analytics_pipeline
.\setup.ps1
```

Script will: aggregate P1/P2/P3 Airflow DAGs → start all services (including **Spark Bronze persistent**) → initialize Postgres/CDC/Kafka/test data → run Silver Merge and Gold (dbt) once → create P2 tables. After completion, **Project 1 / 2 / 3 are all ready to use**.

To start containers only (without initialization):

```bash
cd project_1_cdc_lakehouse_and_dbt_analytics_pipeline/platform/local
docker compose up -d
```

Wait about 45s for MinIO/Airflow/Spark to be ready.

**Running dbt in Airflow**: Image has `dbt-core` and `dbt-trino` installed, and mounts **project_2_metrics_api_and_reverse_etl** dbt to `/opt/airflow/dbt` (volume path `../../../project_2_metrics_api_and_reverse_etl/analytics/dbt`, need to execute `docker compose` from `platform/local`). After first use or Dockerfile changes, rebuild: `docker compose build airflow-init`, then `docker compose up -d`.

## Services and ports — all containers required

**All containers are required** — the stack will not function correctly if any container is removed.

| Service           | Container               | Host port | Used by | Required |
|-------------------|-------------------------|-----------|---------|----------|
| Postgres          | postgres                | **5432**  | P1 (OLTP), P2 (Reverse ETL), Airflow (metadata) |  Yes |
| Zookeeper         | zookeeper               | 2181      | P1 (Kafka) |  Yes |
| Kafka             | kafka                   | **9092**, 29092 | P1 (CDC), P2 (Reverse ETL) |  Yes |
| Kafka Connect     | kafka-connect           | **8083**  | P1 (Debezium) |  Yes |
| MinIO             | minio                   | **9000**, 9001 | P1 (Iceberg), Trino (Iceberg) |  Yes |
| MinIO Init        | minio-init              | —         | Creates `warehouse` bucket |  Yes (one-off) |
| Iceberg REST      | iceberg-rest            | **8181**  | Trino catalog (P2, P3) |  Yes |
| Trino             | trino                   | **8080**  | P2 (Metrics API, dbt, Reverse ETL), P3 (quality gate) |  Yes |
| Airflow DB Create | airflow-db-create       | —         | Creates `airflow` DB |  Yes (one-off) |
| Airflow Init      | airflow-init            | —         | Initializes Airflow DB |  Yes (one-off) |
| Airflow Webserver | airflow-webserver       | **8081**  | P2 (metric_publish_gate), P3 (quality_gate_enforcement) |  Yes |
| Airflow Scheduler | airflow-scheduler       | —         | Runs Airflow DAGs (P2, P3) |  Yes |
| Spark             | spark                   | —         | P1 Bronze persistent (CDC→Kafka→Bronze automatic) |  Yes |

Postgres is exposed as **5432** on the host so Project 2 can use `POSTGRES_PORT=5432`. If host 5432 is already in use, change the compose mapping (e.g. `55432:5432`) and set `POSTGRES_PORT=55432` in Project 2.

## Project 2 connection (defaults)

- **Trino**: `TRINO_HOST=localhost`, `TRINO_PORT=8080`, `TRINO_USER=admin`, `TRINO_CATALOG=iceberg`, `TRINO_SCHEMA=mart_mart` (P1/P2 dbt writes to `mart_mart`)
- **Postgres**: `POSTGRES_HOST=localhost`, `POSTGRES_PORT=5432`, `POSTGRES_DB=project1`, `POSTGRES_USER=postgres`, `POSTGRES_PASSWORD=postgres`
- **Kafka**: `KAFKA_BOOTSTRAP_SERVERS=localhost:9092`
- **Airflow**: http://localhost:8081 (admin / admin)

**Prerequisite**: Complete Project 1 first (Silver + register to REST + Gold), Trino needs `iceberg.mart_mart.*` tables.

**Project 2 completion steps** (on host, execute from `project_2_metrics_api_and_reverse_etl` directory):

1. **Environment**: `cp env.example .env`, confirm `TRINO_SCHEMA=mart_mart`.
2. **customer_segments table** (can skip if setup.ps1 already ran):  
   `Get-Content project_1_cdc_lakehouse_and_dbt_analytics_pipeline\platform\local\sql\02-customer_segments.sql | docker exec -i postgres psql -U postgres -d project1`
3. **dbt**: `cd analytics/dbt` → `dbt deps` → `dbt run` → `dbt test` (need dbt-trino installed, Trino available).
4. **Metrics API**: `cd services/metrics_api` → `pip install -r requirements.txt` → `$env:TRINO_HOST="localhost"; uvicorn app.main:app --host 0.0.0.0 --port 8000`, then access `http://localhost:8000/health`, `http://localhost:8000/kpi?date=2026-01-15&version=v1`.
5. **Reverse ETL**: `cd reverse_etl` → `pip install -r requirements.txt` → `python postgres/upsert_segments.py` or `python kafka/publish_segments.py`.
6. **Airflow**: Trigger DAG `metric_publish_gate` at http://localhost:8081 (need DAGs aggregated to `platform/local/airflow-dags/`).

**Reverse ETL table**: Create `customer_segments` in `project1` (one-time):

```bash
docker exec -i postgres psql -U postgres -d project1 < platform/local/sql/02-customer_segments.sql
```

Or from repo root:  
`cat project_1_cdc_lakehouse_and_dbt_analytics_pipeline/platform/local/sql/02-customer_segments.sql | docker exec -i postgres psql -U postgres -d project1`

## Project 3 connection

- **Trino**: same as Project 2 (`localhost:8080`, catalog `iceberg`, schema `mart_mart`).
- **Airflow**: http://localhost:8081 for DAG `quality_gate_enforcement`.

## Project 1 manually run Silver / Gold again

Spark is persistent by default (Bronze automatically consumes CDC). When you need to run Silver or Gold again:

```bash
# Silver Merge (once)
docker compose run --rm spark sh -c "/opt/spark/bin/spark-submit --master local[*] --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2,org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,org.apache.hadoop:hadoop-aws:3.3.4 /app/streaming/spark/silver_merge/merge_silver.py"

# Gold (dbt)
docker compose --profile gold run --rm dbt sh -c "pip install --no-cache-dir dbt-trino && cd /app/analytics/dbt && rm -rf dbt_packages && dbt deps --profiles-dir /app/analytics/dbt && dbt run --profiles-dir /app/analytics/dbt"
```

Can also trigger DAG **backfill** (Silver → Gold) in Airflow (http://localhost:8081).

## Layout

- `docker-compose.yml` — all services (including Spark default startup)
- `airflow-dags/` — P1/P2/P3 DAGs aggregation directory (populated by setup.ps1)
- `trino/catalog/iceberg.properties` — Iceberg catalog for MinIO (P2/P3)
- `sql/02-customer_segments.sql` — table for P2 Reverse ETL (setup.ps1 will execute)
