# Data Engineer Portfolio — Projects 1, 2, 3

This repository contains three production-grade data engineering projects: **CDC Lakehouse + dbt** (P1), **Metrics API + Reverse ETL** (P2), and **Data Contracts + Quality Gates** (P3). Each section below follows the same structure (Overview, Data & Problem Setup, System Design, Key Methods, API/Outputs, Results, Future Directions, PowerShell run).

---

# Project 1 – Real-time CDC Lakehouse & dbt Analytics Pipeline

---

### 1. Project Overview – What & Why

- **Goal**: Build a **production-grade real-time CDC lakehouse** that ingests OLTP changes into a Bronze/Silver/Gold stack, with **contract validation**, **idempotent merge**, and **analytics-ready marts**.
- **Tasks**:
  - Capture **PostgreSQL** changes via **Debezium** → **Kafka** (CDC event bus).
  - **Bronze**: Spark Structured Streaming reads Debezium JSON, validates against **data contracts** (fail-fast), writes append-only to **Iceberg** `bronze.raw_cdc` with `event_uid`, `entity_key`, `ordering_key`, checkpoint recovery.
  - **Silver**: Batch Spark job reads Bronze, dedupes by `ordering_key`, **MERGE INTO** entity tables (`silver.users`, `silver.orders`, `silver.payments`); supports **deletes** (op='d') and idempotent replay.
  - **Gold**: **dbt** models (stg → int → mart) produce `dim_users`, `fct_orders`, `fct_payments`, `mart_kpis_daily`; schema tests and custom tests gate quality.
- **Form factor**: **Batch/streaming pipelines** (no online scoring API); outputs are **Iceberg tables** queryable via **Trino**. Orchestration via **Airflow** (maintenance, quality gate, reconciliation, backfill). Optional **K8s** deploy (Kustomize dev/stg/prod).

---

### 2. Data & Problem Setup

- **Data source**: **PostgreSQL** OLTP database (local Docker or external), with **logical replication** (`wal_level=logical`). Source schema and seed data are defined in `infra/sql/project1.sql`.
- **Raw data (high level)**:
  - **users**: `user_id`, `email`, `status`, `created_at`, `updated_at`
  - **orders**: `order_id`, `user_id`, `order_ts`, `status`, `total_amount`, `updated_at`
  - **payments**: `payment_id`, `order_id`, `amount`, `status`, `failure_reason`, `updated_at`
- **Problem formulation**:
  - **CDC events**: Debezium emits one message per row change with envelope `{ op, ts_ms, source, before, after }` (op: c/u/d/r).
  - **Ordering**: Deterministic `ordering_key` (lsn → updated_at → partition|offset) for dedupe and idempotent merge.
  - **Contracts**: YAML contracts per entity (PK, required fields, op semantics, evolution) so invalid events fail fast at ingest.

#### 2.1 Kafka topics (Debezium)

After the Debezium connector is registered, Kafka has one topic per table:

| Topic | Description |
|-------|-------------|
| `dbserver_docker.public.users` | CDC for users |
| `dbserver_docker.public.orders` | CDC for orders |
| `dbserver_docker.public.payments` | CDC for payments |

#### 2.2 Lakehouse table layout

- **Bronze**: `iceberg.bronze.raw_cdc` — one row per CDC event; columns include `event_uid`, `entity`, `entity_key`, `ordering_key`, `kafka_*`, `op`, `ts_ms`, `source`, `before`, `after`, `ingest_time`; partitioned by `days(ingest_time)`.
- **Silver**: `iceberg.silver.users`, `iceberg.silver.orders`, `iceberg.silver.payments` — one row per entity (SCD1); business columns plus `_bronze_event_uid`, `_bronze_ordering_key`, `_silver_updated_at`.
- **Gold**: `iceberg.stg.*`, `iceberg.int.*`, `iceberg.mart.*` — dbt-generated (dim_users, fct_orders, fct_payments, mart_kpis_daily, etc.).

---

### 3. System Design & Modules (`project_1_cdc_lakehouse_and_dbt_analytics_pipeline`)

- **3.1 Infrastructure – `infra/`**
  - `infra/sql/project1.sql`: Postgres DDL (users, orders, payments) and `wal_level=logical`.
  - `infra/terraform/`: Optional IaC (local/dev/prod) for MinIO or AWS S3.

- **3.2 CDC connector – `connectors/debezium/`**
  - `configs/project_1_connector.json`: Debezium Postgres Source Connector (topic prefix, table.include.list, snapshot.mode=initial, pgoutput).

- **3.3 Data contracts – `contracts/cdc/`**
  - `users.yaml`, `orders.yaml`, `payments.yaml`: CDC event contracts (PK, required envelope fields, op semantics, payload rules, schema evolution).

- **3.4 Streaming layer – `streaming/spark/`**
  - **Bronze ingest** (`bronze_ingest/`):
    - `ingest_raw_cdc.py`: Entry script (spark-submit).
    - `job.py`: Build SparkSession (Iceberg + S3/MinIO), ensure Bronze table, readStream from Kafka, mapInPandas (parse + validate), writeStream to Iceberg with checkpoint.
    - `config.py`: BronzeConfig from env (Kafka, Iceberg warehouse, checkpoint, contracts dir).
    - `parse_debezium.py`: event_uid, entity_key, ordering_key from Debezium envelope.
    - `contract_validate.py`: load_contracts(), validate_event() against contracts (fail-fast).
  - **Silver merge** (`silver_merge/`):
    - `merge_silver.py`: Entry script.
    - `job.py`: build_spark(), ensure_silver_tables(), run_batch() — read Bronze, per-entity build_latest_events_df (window dedupe), merge_entity() (DELETE for op='d', MERGE for c/u/r).
    - `config.py`: SilverConfig (Iceberg, S3, checkpoint).
    - `parse_bronze.py`: build_latest_events_df(), parse after JSON to Silver row.

- **3.5 Lakehouse DDL – `lakehouse/iceberg/`**
  - `ddl/bronze_raw_cdc.sql`, `ddl/silver_users.sql`, `silver_orders.sql`, `silver_payments.sql`: Reference DDL for Bronze and Silver (job.py can create tables inline as well).

- **3.6 Analytics layer – `analytics/dbt/`**
  - **Staging**: `models/stg/stg_users.sql`, `stg_orders.sql`, `stg_payments.sql` — read from Silver, type casting, null handling, enum normalization.
  - **Intermediate**: `models/int/int_users.sql`, `int_orders.sql`, `int_payments.sql` — business logic (status normalization, filter deleted, amount checks).
  - **Mart**: `models/mart/dim_users.sql`, `fct_orders.sql`, `fct_payments.sql`, `mart_kpis_daily.sql` — dimensions, facts, daily KPIs.
  - **Tests**: `models/schema.yml` (not_null, unique, relationships, accepted_values); `tests/test_payments_amount_check.sql`, `test_kpi_completeness.sql`.
  - **Config**: `dbt_project.yml`, `profiles.yml` (Trino/Iceberg), `packages.yml` (dbt_utils, dbt_expectations).

- **3.7 Orchestration – `orchestration/airflow/dags/`**
  - `maintenance_iceberg.py`: Compact Bronze/Silver, expire snapshots, remove orphan files.
  - `quality_gate_cdc.py`: Run dbt test, block on failure, optional alerting.
  - `reconciliation.py`: Bronze/Silver/Gold counts and continuity checks → report under `recon/`.
  - `backfill.py`: Manual trigger to re-run Silver merge and/or Gold (dbt run).

- **3.8 Observability – `observability/`**
  - Datadog monitors (consumer lag, freshness, completeness, job success) and SLO-aligned dashboard (config as code).

- **3.9 Platform & run – `platform/`**
  - **Local**: `platform/local/docker-compose.yml` — Postgres, Kafka, Kafka Connect (Debezium), MinIO, Trino, Airflow; Spark via `docker compose --profile bronze run --rm spark`.
  - **K8s**: `platform/k8s/base/` + `overlays/dev|stg|prod/` — Kustomize for Spark Bronze/Silver, MinIO (see `Makefile` targets `deploy-k8s-*`).

---

### 4. Key Methods & Design Choices

- **Target design**
  - **Bronze**: Append-only, immutable CDC log; `event_uid` and `ordering_key` support replay and idempotency.
  - **Silver**: SCD1 per entity; MERGE uses `_bronze_ordering_key` so replay does not double-apply.
  - **Gold**: dbt as single place for analytics logic and quality tests.

- **Contract-first ingest**
  - Events validated in the streaming job (mapInPandas); violation raises and stops the job so bad data does not land.

- **Algorithms / patterns**
  - **Bronze**: Spark readStream (Kafka) → mapInPandas (parse_debezium + contract_validate) → writeStream Iceberg; checkpoint for exactly-once semantics and recovery.
  - **Silver**: Batch read Bronze → window (ROW_NUMBER by entity_key, ORDER BY ordering_key DESC) → take latest → split op='d' (DELETE) vs c/u/r (MERGE INTO with ordering_key comparison).
  - **Gold**: dbt with Trino (or Spark SQL) against Iceberg; materializations: view (stg/int), table (mart).

- **Quality & MLOps**
  - Data contracts (YAML) and feature/schema discipline in dbt (schema.yml + custom tests).
  - Promotion gate via Airflow quality_gate_cdc (dbt test must pass).
  - Reconciliation scripts and demo scripts (failure recovery, replay idempotency, schema evolution) for validation and evidence.

---

### 5. Outputs & How to Query

- **No REST scoring API**: This project is a pipeline; consumption is via **SQL** (Trino or Spark) on Iceberg tables.

- **Key outputs**
  - **Bronze**: `iceberg.bronze.raw_cdc` — full CDC log.
  - **Silver**: `iceberg.silver.users`, `iceberg.silver.orders`, `iceberg.silver.payments` — current state per entity.
  - **Gold**: `iceberg.mart.dim_users`, `iceberg.mart.fct_orders`, `iceberg.mart.fct_payments`, `iceberg.mart.mart_kpis_daily` — analytics marts.

- **Example queries (Trino, schema names may vary by dbt profile)**
  - Recent daily KPIs:
    ```sql
    SELECT * FROM iceberg.mart.mart_kpis_daily ORDER BY kpi_date DESC LIMIT 10;
    ```
  - User dimension with order count:
    ```sql
    SELECT u.user_id, u.email, u.status, COUNT(o.order_id) AS order_count
    FROM iceberg.mart.dim_users u
    LEFT JOIN iceberg.mart.fct_orders o ON u.user_id = o.user_id
    GROUP BY u.user_id, u.email, u.status;
    ```

- **Reconciliation reports**
  - Generated by `scripts/run_reconciliation.sh` (invoked by Airflow or manually); output under `recon/` (e.g. Bronze/Silver row counts, Gold KPI checksums).

- **Monitoring**
  - Datadog: consumer lag, freshness, completeness, job success; dashboard aligned to SLOs.
  - Airflow: DAG success/failure for maintenance, quality gate, reconciliation, backfill.

---

### 6. Results & Business Impact

- **Pipeline correctness**: Event continuity (event_uid), controlled duplicates (idempotent Silver merge), eventual consistency; demo scripts validate failure recovery and replay idempotency.
- **SLA**: P95 latency targets and completeness checks (dbt tests + reconciliation); observability in place.
- **Operability**: One-command Docker Compose start; K8s Kustomize for dev/stg/prod; config via env vars; runbooks and docs in `docs/`, `runbook/`.

---

### 7. Future Directions – What I Would Do Next

- **Limitations & assumptions**
  - Single Postgres source; multi-source or multi-region would need connector and schema alignment.
  - Silver is batch; true streaming MERGE (e.g. Flink/Iceberg) could reduce latency further.
  - Demo data and demos are synthetic; production would add more reconciliation and alerting.

- **Pipeline & platform**
  - Add schema evolution automation (contract versioning, backward-compatible adds).
  - Strengthen CI (e.g. SQLFluff, dbt test on PR; contract validation in GitHub Actions).
  - Optional online layer: expose Gold (or Silver) via a thin read API or Reverse ETL (see Project 2).

- **Governance**
  - Align with Project 3 (data contracts + quality gates) for a unified governance story across CDC and metrics.

---

### 8. PowerShell: from clone to run

```powershell
# 1) Start platform (Postgres, Kafka, Connect, MinIO, Trino, Airflow)
cd project_1_cdc_lakehouse_and_dbt_analytics_pipeline\platform\local
docker compose up -d
cd ..\..\..

# 2) Initialize Postgres (tables + wal_level=logical)
docker cp project_1_cdc_lakehouse_and_dbt_analytics_pipeline/infra/sql/project1.sql postgres:/tmp/project1.sql
docker exec -it postgres psql -U postgres -d project1 -f /tmp/project1.sql

# 3) Register Debezium connector
curl -X POST http://localhost:8083/connectors -H "Content-Type: application/json" -d "@project_1_cdc_lakehouse_and_dbt_analytics_pipeline/connectors/debezium/configs/project_1_connector.json"

# 4) (Optional) Insert test data
docker exec -it postgres psql -U postgres -d project1 -c "
INSERT INTO public.users(user_id, email, status, created_at, updated_at) VALUES (1, 'u1@example.com', 'active', now(), now());
INSERT INTO public.orders(order_id, user_id, order_ts, status, total_amount, updated_at) VALUES (1, 1, now(), 'created', 123.45, now());
INSERT INTO public.payments(payment_id, order_id, amount, status, failure_reason, updated_at) VALUES (1, 1, 123.45, 'paid', null, now());
"

# 5) Run Bronze ingest (long-running; use profile bronze from platform/local)
cd project_1_cdc_lakehouse_and_dbt_analytics_pipeline\platform\local
docker compose --profile bronze up -d
# Wait for minio-init (~15s), then:
docker compose --profile bronze run --rm spark
# Ctrl+C to stop. Checkpoint allows resume.

# 6) Run Silver merge (batch, from repo root with Spark/Python env)
cd c:\Users\qwert\OneDrive\Desktop\folder\data_engineer_project_1_2_3
# If Spark/MinIO config set: spark-submit project_1_cdc_lakehouse_and_dbt_analytics_pipeline/streaming/spark/silver_merge/merge_silver.py
# Or run via Airflow / backfill DAG after Bronze has data.

# 7) Run dbt (Gold) — from project_1 analytics/dbt, with Trino pointing to Iceberg
cd project_1_cdc_lakehouse_and_dbt_analytics_pipeline\analytics\dbt
dbt deps
dbt run
dbt test
```

For full reset: `docker compose down -v` then `docker compose up -d`. See `project_1_cdc_lakehouse_and_dbt_analytics_pipeline/README.md` and `platform/local/README.md` for more options (e.g. Makefile, acceptance tests, demo scripts).

---

# Project 2 – Metrics Service + Reverse ETL

---

### 1. Project Overview – What & Why

- **Goal**: Build a **metrics service and reverse ETL** on top of Project 1 Gold: expose **versioned KPIs and user segments** via an API, and **write segments back** to Postgres and Kafka under a **quality gate**.
- **Tasks**:
  - **dbt semantic layer**: Direct ref to Project 1 Gold (no copy); staging → intermediate (user segmentation) → mart (`mart_kpis_daily_v1`, `mart_user_segments`).
  - **Metrics API**: FastAPI + Trino; versioned endpoints for KPI and user-segment queries.
  - **Reverse ETL**: Idempotent Postgres upsert (`customer_segments`) and Kafka publish (`segment_updates`, keyed by `user_id`).
  - **Quality gate**: Airflow DAG runs dbt tests, completeness check, release log insert, then Reverse ETL; any failure blocks release.
- **Form factor**: **Online API** (GET /kpi, GET /user_segment, GET /versions) + **batch Reverse ETL** (script or DAG). Depends on **Project 1** Gold and **Trino**; optional Postgres/Kafka for write-back. K8s Kustomize (dev/prod) for API deploy.

---

### 2. Data & Problem Setup

- **Data source**: **Project 1 Gold** Iceberg tables — `iceberg.mart.mart_kpis_daily`, `iceberg.mart.dim_users`, `iceberg.mart.fct_orders`, `iceberg.mart.fct_payments`. No separate raw ingest; dbt reads these directly (same catalog/schema, e.g. `mart_mart`).
- **Problem formulation**:
  - **Unified metrics**: All KPIs from one versioned mart; user segments (high-value, churn risk, active) for targeting.
  - **Versioning**: Metric version (e.g. v1) and release tracking in `metric_release_log`.
  - **Write-back**: Segments pushed to operational systems (Postgres for CRM, Kafka for event-driven systems) with idempotency.

#### 2.1 dbt semantic layer (Project 2)

| Layer | Models | Source |
|-------|--------|--------|
| Staging | stg_kpis_daily, stg_users, stg_orders, stg_payments | Project 1 Gold (mart_kpis_daily, dim_users, fct_orders, fct_payments) |
| Intermediate | int_user_segments | User segmentation (high-value 90d GMV ≥1000, churn risk 30d no orders, active 7d orders) |
| Mart | mart_kpis_daily_v1, mart_user_segments | Versioned KPI mart; user-segment mart for API and Reverse ETL |

#### 2.2 Reverse ETL targets

- **Postgres**: table `customer_segments` — upsert key `(user_id, segment_date)`; idempotent.
- **Kafka**: topic `segment_updates` — message key `user_id` for per-user ordering.

---

### 3. System Design & Modules (`project_2_metrics_api_and_reverse_etl`)

- **3.1 Analytics layer – `analytics/dbt/`**
  - **Staging**: `models/stg/stg_kpis_daily.sql`, `stg_users.sql`, `stg_orders.sql`, `stg_payments.sql` — direct ref to Project 1 Gold (iceberg.mart.*).
  - **Intermediate**: `models/int/int_user_segments.sql` — segmentation logic.
  - **Mart**: `models/mart/mart_kpis_daily_v1.sql`, `mart_user_segments.sql` — versioned KPI and segment marts.
  - **Tests**: `models/schema.yml` (not_null, unique, relationships, accepted_values); custom tests (kpi_completeness, payment_amount_consistency).
  - **Config**: `dbt_project.yml`, `profiles.yml` (Trino/Iceberg, schema e.g. mart_mart), `packages.yml`.

- **3.2 Metrics API – `services/metrics_api/`**
  - `app/main.py`: FastAPI app; `execute_trino_query()` for Trino; endpoints: `/health`, `/kpi`, `/user_segment`, `/versions`, `/metrics/list`.
  - Config from env: `TRINO_HOST`, `TRINO_PORT`, `TRINO_SCHEMA` (e.g. mart_mart), cache TTL, query timeout.
  - `requirements.txt`, `Dockerfile` for containerized deploy.

- **3.3 Reverse ETL – `reverse_etl/`**
  - `postgres/upsert_segments.py`: Read segments from Trino (`mart_user_segments`), upsert to Postgres `customer_segments` (ON CONFLICT DO UPDATE); idempotent.
  - `kafka/publish_segments.py`: Publish segment rows to Kafka topic `segment_updates`, keyed by `user_id`.
  - `requirements.txt` for deps.

- **3.4 Orchestration – `orchestration/airflow/dags/`**
  - `metric_publish_gate.py`: DAG steps — run_dbt_tests → check_completeness → insert_release_log (iceberg.mart.metric_release_log) → publish_reverse_etl (Postgres + Kafka). Any step fail → block release.

- **3.5 Lakehouse – `lakehouse/`**
  - `ddl/metric_release_log.sql`: Release log table DDL (release_id, metric_version, git_commit, dbt_tests_passed, completeness_check_passed, etc.).

- **3.6 Contracts – `contracts/metrics/`**
  - `kpis.yaml`, `user_segments.yaml`, `release_log.yaml`: Metric/segment structure and rules (for Project 3 validator or local checks).

- **3.7 Platform – `platform/k8s/`**
  - Kustomize base + overlays dev/prod; Metrics API Deployment and Service.

- **3.8 Docs & scripts – `docs/`, `scripts/`, `runbook/`**
  - Architecture, SLO, release process, acceptance criteria; `setup.sh`, `demo_metric_release.sh`, `demo_reverse_etl.sh`, `demo_api_latency.sh`.

---

### 4. Key Methods & Design Choices

- **Target design**
  - Single source of truth: Project 1 Gold; Project 2 does not copy data, only adds semantic layer and write-back.
  - Versioned marts (e.g. mart_kpis_daily_v1) and release log for traceability and rollback.

- **API design**
  - Trino as query engine; FastAPI wraps parameterized SQL (date, version, segment name). Optional cache (e.g. TTL) for latency.

- **Reverse ETL**
  - Idempotent upsert (Postgres) and keyed publish (Kafka) so retries do not create duplicates; safe to run after quality gate.

- **Quality & MLOps**
  - Quality gate DAG blocks release on dbt test or completeness failure; release log records every successful publish for auditing.

---

### 5. API & Outputs

- **Synchronous API – `GET /kpi`**
  - **Input**: `date`, `version` (e.g. v1).
  - **Output**: JSON with KPI fields for that date (from mart_kpis_daily_v1).

- **Synchronous API – `GET /user_segment`**
  - **Input**: `segment` (e.g. high_value, churn_risk, active), `version`.
  - **Output**: JSON list of users in that segment (from mart_user_segments).

- **Metadata – `GET /versions`, `GET /metrics/list`, `GET /health`**
  - Available versions, metric list, health check.

- **Database / audit outputs**
  - **Release log**: Each quality-gate pass writes a row to `iceberg.mart.metric_release_log` (release_id, metric_version, git_commit, flags, timestamp).
  - **Reverse ETL**: Postgres `customer_segments` and Kafka `segment_updates` hold the written-back segment data.

- **Example queries (Trino)**
  - Recent releases:
    ```sql
    SELECT * FROM iceberg.mart.metric_release_log ORDER BY release_ts DESC LIMIT 10;
    ```

---

### 6. Results & Business Impact

- **Unified metrics**: All KPIs and segments from one pipeline; versioning and release log support governance.
- **SLA**: API p95 latency target (e.g. <300ms); KPI freshness; completeness checks before release.
- **Operability**: Quality gate blocks bad releases; idempotent Reverse ETL allows safe retries; K8s deploy for API.

---

### 7. Future Directions – What I Would Do Next

- **Limitations & assumptions**
  - Depends on Project 1 Gold; schema/version alignment must be maintained.
  - Reverse ETL is batch/scheduled; real-time sync would need change-data or streaming.

- **Improvements**
  - Add rate limiting and auth for Metrics API; expand segment definitions and A/B versioning.
  - Integrate with Project 3 quality gate (contract validation, cross-project dbt tests).

---

### 8. PowerShell: from clone to run

```powershell
# Prerequisites: Project 1 running, Gold tables exist, Trino reachable (e.g. localhost:8080).

# 1) Setup and env
cd project_2_metrics_api_and_reverse_etl
.\scripts\setup.sh
Copy-Item .env.example .env
# Edit .env: TRINO_HOST, TRINO_PORT, TRINO_SCHEMA, POSTGRES_*, KAFKA_* if using Reverse ETL

# 2) dbt
cd analytics\dbt
dbt deps
dbt run
dbt test
cd ..\..

# 3) Start Metrics API
cd services\metrics_api
pip install -r requirements.txt
$env:TRINO_HOST="localhost"; $env:TRINO_PORT="8080"; $env:TRINO_SCHEMA="mart_mart"
uvicorn app.main:app --host 0.0.0.0 --port 8000
# API: http://localhost:8000

# 4) Test API (another terminal)
Invoke-RestMethod -Uri "http://localhost:8000/health"
Invoke-RestMethod -Uri "http://localhost:8000/kpi?date=2026-01-15&version=v1"
Invoke-RestMethod -Uri "http://localhost:8000/user_segment?segment=high_value&version=v1"

# 5) Reverse ETL (optional; requires Postgres + Kafka)
cd project_2_metrics_api_and_reverse_etl\reverse_etl
pip install -r requirements.txt
$env:POSTGRES_HOST="localhost"; $env:POSTGRES_PASSWORD="postgres"
python postgres/upsert_segments.py
python kafka/publish_segments.py
```

See `project_2_metrics_api_and_reverse_etl/README.md` and `RUN_LOCAL.md` for full options (Makefile, demos, K8s).

---

# Project 3 – Data Contracts + Quality Gates + CI

---

### 1. Project Overview – What & Why

- **Goal**: Provide **governance and quality gates** across Projects 1 and 2: **data contract validation** (CDC and metrics), **unified quality gate DAG** (dbt tests, custom checks, completeness), and **CI** so bad changes cannot merge or release.
- **Tasks**:
  - **Contract validator**: Python tool to validate YAML contracts (CDC events, metrics); check required fields, op semantics, PK, schema, evolution; usable in CI and Airflow.
  - **Quality gate DAG**: Airflow DAG `quality_gate_enforcement` — validate contracts → run dbt tests (P1 + P2) → run custom quality checks (Trino) → check completeness → enforce gate decision; any failure blocks release.
  - **CI (GitHub Actions)**: Lint (Python/SQL), contract validation, unit tests (P1 + validator), dbt compile/test (P1 + P2); all must pass before PR merge.
- **Form factor**: **No standalone service**; validator runs in CI and inside Airflow tasks. DAG runs on **Project 1’s platform** (Airflow); contracts and DAG code live in `project_3_data_contracts_and_quality_gates/`.

---

### 2. Data & Problem Setup

- **Data source**: **Contracts** (YAML) and **downstream data** (Iceberg via Trino). No new raw data; Project 3 validates structure and quality of P1/P2 outputs.
- **Contract definitions**:
  - **CDC contracts**: `contracts/cdc/users.yaml`, `orders.yaml`, `payments.yaml` — Debezium envelope (op, ts_ms, source), payload (after/before), PK, schema fields, evolution policy.
  - **Metrics contracts**: `contracts/metrics/kpis.yaml`, `user_segments.yaml` — metric/segment structure and rules.
- **Problem formulation**:
  - **Contracts first**: Define expected shape and rules before code changes; validator fails fast on invalid events or contract files.
  - **Single gate**: One DAG that runs all checks (contracts, dbt, custom SQL, completeness); release only if all pass.

#### 2.1 Quality gate steps (Airflow DAG)

| Step | Description | Blocking |
|------|-------------|----------|
| validate_contracts | Run contract validator on contracts dir | Yes |
| run_dbt_tests_project1 | dbt test in P1 project | Yes (or skip if not mounted) |
| run_dbt_tests_project2 | dbt test in P2 project | Yes (or skip if not mounted) |
| run_custom_quality_checks | Trino queries (referential integrity, amounts, etc.) | Yes |
| check_completeness | Expected partitions exist in marts | Yes |
| enforce_gate_decision | Release allowed only if all above passed | — |

---

### 3. System Design & Modules (`project_3_data_contracts_and_quality_gates`)

- **3.1 Contracts – `contracts/`**
  - `cdc/`: users.yaml, orders.yaml, payments.yaml — CDC event contracts.
  - `metrics/`: kpis.yaml, user_segments.yaml — metrics contracts.
  - `rules.md`, `schema_evolution.md`: Contract rules and evolution policy docs.

- **3.2 Contract validator – `tools/contract_validator/`**
  - `contract_validator.py`: Load YAML contracts; validate CDC events (required fields, op, payload, PK, schema); validate schema evolution; CLI (`--contracts-dir`, `--contract`, `--event`).
  - `requirements.txt`: PyYAML, etc.

- **3.3 Quality gate DAG – `orchestration/airflow/dags/`**
  - `quality_gate_enforcement.py`: DAG definition; tasks call validator, dbt test (P1/P2 dirs), custom checks (Trino), completeness (Trino); final task enforces gate decision. Schedule: hourly; env vars for PROJECT_ROOT, PROJECT1_DBT_DIR, PROJECT2_DBT_DIR, TRINO_*.

- **3.4 Quality gate docs – `quality_gates/`**
  - `dbt/tests.md`, `completeness/checks.md`, `rules.md`: What is tested and how.

- **3.5 CI – `ci/github_actions/`**
  - `ci.example.yml`: Example workflow (lint, contract validation, unit tests, dbt compile/test); repo may have `.github/workflows/ci.yml` based on this.

- **3.6 Scripts – `scripts/`**
  - `demo_contract_violation.sh`, `demo_quality_gate_failure.sh`, `demo_release_block.sh`: Demos for contract validation, gate failure, and release blocking.

- **3.7 Docs – `docs/`**
  - `architecture.md`, `slo.md`, `runbook.md`: Governance architecture, SLO, operational runbook.

- **3.8 Evidence – `evidence/`**
  - `demos/`, `validation/`: Demo and validation evidence.

---

### 4. Key Methods & Design Choices

- **Target design**
  - **Contracts first**: YAML as single source of truth for event/metric shape; validator used in CI and in Airflow so same rules apply everywhere.
  - **Strict gates**: Any failure in the DAG fails the run and blocks release; no partial pass.

- **Validator design**
  - Pure Python; no runtime dependency on Spark or dbt. Validates envelope (op, ts_ms, source), payload (after/before), PK, nullable/allowed_values; optional schema evolution check.

- **Integration**
  - P3 DAG runs on P1’s Airflow; P3 and P1/P2 code can live in same repo or be mounted so DAG finds contracts and dbt projects. Skip tasks gracefully if a project dir is not present (e.g. in minimal containers).

---

### 5. API & Outputs

- **No REST API**: Project 3 is tooling and orchestration; “outputs” are validation results and gate decisions.

- **Validator CLI**
  - `python contract_validator.py --contracts-dir ../../contracts` — validate all contracts.
  - `python contract_validator.py --contract path/to/orders.yaml --event event.json` — validate one event against one contract.
  - Exit code 0 = pass; non-zero = violations (printed to stderr/stdout).

- **Quality gate outputs**
  - **Airflow**: DAG run success/failure; task logs contain validator output, dbt test results, custom check results.
  - **Release decision**: Only “release allowed” when all tasks pass; otherwise “release blocked.”

- **CI outputs**
  - GitHub Actions: Lint, contract validation, unit tests, dbt compile/test results; PR cannot merge if any step fails.

---

### 6. Results & Business Impact

- **Contract validation**: All contracts and event samples valid; violations caught in CI or at gate.
- **Release safety**: Bad data or broken dbt/models cannot release; single gate reduces coordination cost.
- **Traceability**: Validation results and gate outcomes in logs and reports; aligns with P1/P2 audit and release log.

---

### 7. Future Directions – What I Would Do Next

- **Limitations & assumptions**
  - DAG depends on P1 platform (Airflow) and optional P1/P2 dbt mounts; fully standalone runner would need packaging or different deployment.
  - Custom checks and completeness logic are Trino/SQL-based; more complex rules may need a small framework.

- **Improvements**
  - Richer contract language (e.g. numeric bounds, cross-field rules); schema evolution automation.
  - Datadog (or similar) integration for gate failure alerts; dashboards for pass rate and latency.

---

### 8. PowerShell: from clone to run

```powershell
# Prerequisites: Project 1 platform running (Airflow, Trino). Optionally Project 2 dbt and data.

# 1) Install validator deps
cd project_3_data_contracts_and_quality_gates\tools\contract_validator
pip install -r requirements.txt

# 2) Validate contracts locally
python contract_validator.py --contracts-dir ..\..\contracts

# 3) Sync P3 DAG to P1 platform and run gate (recommended: use P3 setup.ps1)
cd ..\..\..\project_3_data_contracts_and_quality_gates
.\setup.ps1
# Follow prompts: sync DAG to project_1_cdc_lakehouse_and_dbt_analytics_pipeline\platform\local\airflow-dags,
# open Airflow UI http://localhost:8081, trigger DAG "quality_gate_enforcement"

# 4) Manual DAG sync (if not using setup.ps1)
Copy-Item project_3_data_contracts_and_quality_gates\orchestration\airflow\dags\*.py `
  project_1_cdc_lakehouse_and_dbt_analytics_pipeline\platform\local\airflow-dags\
# Then in Airflow: unpause and trigger "quality_gate_enforcement"

# 5) Run demos (Bash or WSL if on Windows)
# ./project_3_data_contracts_and_quality_gates/scripts/demo_contract_violation.sh
# ./project_3_data_contracts_and_quality_gates/scripts/demo_quality_gate_failure.sh
# ./project_3_data_contracts_and_quality_gates/scripts/demo_release_block.sh
```

See `project_3_data_contracts_and_quality_gates/README.md` for One-Command Completion, env vars (TRINO_SCHEMA=mart_mart, PROJECT1_DBT_DIR, PROJECT2_DBT_DIR), and acceptance criteria.
