# Project 2: Metrics Service + Reverse ETL (Production-Grade)

## Status — v1.0 (Production-Ready)

- **v0.1** : dbt semantic layer — direct ref to Project 1 Gold, user segmentation (stg/int/mart)
- **v0.2** : **Metrics API** — FastAPI + Trino, versioned KPI and user-segment queries
- **v0.3** : **Reverse ETL** — Postgres upsert + Kafka publish, idempotent
- **v0.4** : **Quality gates** — Airflow DAG (dbt tests, completeness, release log)
- **v0.5** : **Demo scripts** — `demo_metric_release.sh`, `demo_reverse_etl.sh`, `demo_api_latency.sh`
- **v0.6** : **Release log** — `metric_release_log` table, version tracking
- **v0.7** : **K8s deploy** — Kustomize overlays (dev/prod), one-command deploy
- **v0.8** : **Docs** — README, architecture, SLO, runbook, component docs

**~98% complete** (implementation 100%, docs done; remaining: runtime testing)

---

## Tech Stack

### Core
- **dbt** — Modeling (semantic layer, refs Project 1 Gold)
- **FastAPI** — Metrics API
- **Trino** — SQL engine (Iceberg, Gold tables)
- **PostgreSQL** — Reverse ETL target (customer_segments)
- **Apache Kafka** — Reverse ETL target (segment_updates)
- **Apache Airflow** 2.x — Orchestration (quality gates, release)
- **Kubernetes** + **Kustomize** — Deploy (dev/prod)

### Storage
- **Apache Iceberg** — Lakehouse (read Project 1 Gold)
- **MinIO** / **AWS S3** — Object storage (via Project 1)

### Languages
- **Python** 3.11+ — FastAPI, Reverse ETL
- **SQL** — dbt, Trino
- **YAML** — dbt, K8s, contracts
- **Bash** — Demos, setup

### Tooling
- **Docker** — Containers
- **Makefile** — One-command targets

See `docs/architecture.md` for details.

---

## Data Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Project 1 Gold layer (Iceberg)                        │
├─────────────────────────────────────────────────────────────────────────┤
│  iceberg.mart.mart_kpis_daily                                           │
│  iceberg.mart.dim_users                                                  │
│  iceberg.mart.fct_orders                                                 │
│  iceberg.mart.fct_payments                                               │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Direct ref (no copy)
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Project 2 dbt semantic layer                          │
├─────────────────────────────────────────────────────────────────────────┤
│  analytics/dbt/models/stg/                                              │
│  └─ stg_kpis_daily → iceberg.mart.mart_kpis_daily                       │
│  └─ stg_users → iceberg.mart.dim_users                                   │
│  └─ stg_orders → iceberg.mart.fct_orders                                 │
│  └─ stg_payments → iceberg.mart.fct_payments                            │
│                                                                          │
│  analytics/dbt/models/int/                                              │
│  └─ int_user_segments: user segmentation                                │
│     • High-value (90d GMV >= 1000)                                       │
│     • Churn risk (30d no orders)                                         │
│     • Active (7d has orders)                                             │
│                                                                          │
│  analytics/dbt/models/mart/                                            │
│  └─ mart_kpis_daily_v1: versioned KPI mart                              │
│  └─ mart_user_segments: user-segment mart                               │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Trino queries
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Metrics API (FastAPI)                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  services/metrics_api/app/main.py                                      │
│  └─ GET /kpi?date=...&version=v1                                        │
│  └─ GET /user_segment?segment=...&version=v1                            │
│  └─ GET /versions                                                       │
│  └─ GET /metrics/list                                                   │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Reverse ETL
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Reverse ETL (Postgres + Kafka)                        │
├─────────────────────────────────────────────────────────────────────────┤
│  reverse_etl/postgres/upsert_segments.py                                │
│  └─ Upsert to customer_segments (idempotent)                             │
│                                                                          │
│  reverse_etl/kafka/publish_segments.py                                  │
│  └─ Publish to segment_updates (keyed by user_id)                        │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Quality gate
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Airflow quality gate                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  orchestration/airflow/dags/metric_publish_gate.py                      │
│  └─ 1. Run dbt tests → block on failure                                  │
│  └─ 2. Check completeness → block on failure                             │
│  └─ 3. Insert release log → record release metadata                      │
│  └─ 4. Publish Reverse ETL → run write-back                              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow (File Call Order)

### Phase 1: dbt semantic layer

**Step 1.1: Run dbt models**
- Files: `analytics/dbt/dbt_project.yml` → `dbt run`
- Config: `analytics/dbt/profiles.yml` (Trino/Iceberg)
- Next: → Staging

**Step 1.2: Staging**
- Files:
  - `analytics/dbt/models/stg/stg_kpis_daily.sql` → `iceberg.mart.mart_kpis_daily`
  - `analytics/dbt/models/stg/stg_users.sql` → `iceberg.mart.dim_users`
  - `analytics/dbt/models/stg/stg_orders.sql` → `iceberg.mart.fct_orders`
  - `analytics/dbt/models/stg/stg_payments.sql` → `iceberg.mart.fct_payments`
- Purpose: Direct ref to Project 1 Gold (no copy)
- Output: Staging views (materialized: view)
- Next: → Intermediate

**Step 1.3: Intermediate**
- File: `analytics/dbt/models/int/int_user_segments.sql`
- Purpose: User segmentation (high-value, churn risk, active)
- Output: Intermediate view (materialized: view)
- Next: → Mart

**Step 1.4: Mart**
- Files:
  - `analytics/dbt/models/mart/mart_kpis_daily_v1.sql` → versioned KPI mart
  - `analytics/dbt/models/mart/mart_user_segments.sql` → user-segment mart
- Purpose: Final marts for Metrics API and Reverse ETL
- Output: Mart tables (materialized: table)
- Next: → Data quality tests

**Step 1.5: Data quality tests**
- Files:
  - `analytics/dbt/models/schema.yml` → schema tests (not_null, unique, relationships, accepted_values)
  - Custom: `test_kpi_completeness`, `test_payment_amount_consistency`
- Purpose: `dbt test`, validate data quality
- Result: Pass → data usable; fail → block release

---

### Phase 2: Metrics API

**Step 2.1: Start Metrics API**
- File: `services/metrics_api/app/main.py`
- Purpose: Start FastAPI service
- Run: `uvicorn app.main:app --host 0.0.0.0 --port 8000`
- Result: API on port 8000

**Step 2.2: Handle API requests**
- File: `services/metrics_api/app/main.py` → `execute_trino_query()`
- Purpose: Handle HTTP, query Trino
- Endpoints:
  - `/kpi?date=...&version=v1` → query `mart_kpis_daily_v1`
  - `/user_segment?segment=...&version=v1` → query `mart_user_segments`
- Result: JSON response

---

### Phase 3: Reverse ETL write-back

**Step 3.1: Read segments from Trino**
- Files: `reverse_etl/postgres/upsert_segments.py` / `reverse_etl/kafka/publish_segments.py`
- Purpose: Query `iceberg.mart.mart_user_segments`
- Result: User segment data

**Step 3.2: Postgres upsert**
- File: `reverse_etl/postgres/upsert_segments.py` → `PostgresSegmentUpserter.upsert_segments()`
- Purpose: Upsert into `customer_segments`
- Method: `ON CONFLICT (user_id, segment_date) DO UPDATE`
- Result: Data in Postgres (idempotent)

**Step 3.3: Kafka publish**
- File: `reverse_etl/kafka/publish_segments.py` → `KafkaSegmentPublisher.publish_segments()`
- Purpose: Publish to `segment_updates` topic
- Method: Key = `user_id` (per-user ordering)
- Result: Messages to Kafka (at-least-once)

---

### Phase 4: Quality gate and release

**Step 4.1: Run dbt tests**
- File: `orchestration/airflow/dags/metric_publish_gate.py` → `run_dbt_tests()`
- Purpose: Run `dbt test`
- Result: Pass → continue; fail → DAG fails, release blocked

**Step 4.2: Check completeness**
- File: `orchestration/airflow/dags/metric_publish_gate.py` → `check_completeness()`
- Purpose: Verify expected partitions exist
- Result: Pass → continue; fail → DAG fails, release blocked

**Step 4.3: Insert release log**
- File: `orchestration/airflow/dags/metric_publish_gate.py` → `insert_release_log()`
- Purpose: Insert into `iceberg.mart.metric_release_log`
- Fields: release_id, metric_version, git_commit, dbt_tests_passed, completeness_check_passed
- Result: Release log recorded

**Step 4.4: Run Reverse ETL**
- File: `orchestration/airflow/dags/metric_publish_gate.py` → `publish_reverse_etl()`
- Purpose: Postgres upsert + Kafka publish
- Result: Data written back to downstream systems

---

## Progress

###  Done (v1.0)

1. **dbt semantic layer**
   -  Staging: direct ref to Project 1 Gold
   -  Intermediate: user segmentation
   -  Mart: versioned KPI mart, user-segment mart
   -  Schema and custom tests

2. **Metrics API**
   -  FastAPI service
   -  Trino integration
   -  Versioned queries
   -  Health and metadata endpoints

3. **Reverse ETL**
   -  Postgres upsert (idempotent)
   -  Kafka publish (ordering)
   -  Error handling and retries

4. **Quality gates**
   -  Airflow DAG
   -  dbt test blocking
   -  Completeness checks
   -  Release log

5. **Release log**
   -  `metric_release_log` table
   -  Version tracking

6. **Demo scripts**
   -  `demo_metric_release.sh`: metric release
   -  `demo_reverse_etl.sh`: Reverse ETL
   -  `demo_api_latency.sh`: API latency

7. **Docs**
   -  README, architecture, SLO, runbook
   -  Component docs (dbt, API, Reverse ETL)
   -  env example, setup script

8. **K8s deploy**
   -  Kustomize (base + dev/prod overlays)
   -  Metrics API Deployment and Service

---

## Quick start

### Prerequisites

1. **Project 1 running**: Gold tables exist
2. **Trino running**: Can query Iceberg
3. **Postgres** (optional): For Reverse ETL
4. **Kafka** (optional): For Reverse ETL

### 1. One-command setup

```bash
# Run setup
./scripts/setup.sh

# Environment
cp .env.example .env
# Edit .env with real values
```

### 2. Set up dbt

```bash
cd analytics/dbt
dbt deps  # Install deps
dbt run   # Run models
dbt test  # Run tests
```

Or use Makefile:

```bash
make dbt-deps
make dbt-run
make dbt-test
```

### 3. Start Metrics API

```bash
cd services/metrics_api
pip install -r requirements.txt
export TRINO_HOST=localhost
export TRINO_PORT=8080
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Or Makefile:

```bash
make api-start
```

### 4. Test API

```bash
# Health check
curl http://localhost:8000/health

# KPI query
curl "http://localhost:8000/kpi?date=2026-01-15&version=v1"

# User segment
curl "http://localhost:8000/user_segment?segment=high_value&version=v1"
```

Or Makefile:

```bash
make api-test
```

### 5. Run Reverse ETL

```bash
# Postgres upsert
cd reverse_etl
export POSTGRES_HOST=localhost
export POSTGRES_PASSWORD=postgres
python postgres/upsert_segments.py
```

Or Makefile:

```bash
make reverse-etl-postgres
make reverse-etl-kafka
```

### 6. Run demo scripts

```bash
# Metric release
./scripts/demo_metric_release.sh

# Reverse ETL demo
./scripts/demo_reverse_etl.sh

# API latency test
./scripts/demo_api_latency.sh
```

Or Makefile:

```bash
make demo-release
make demo-reverse-etl
make demo-api-latency
```

---

## Acceptance criteria

-  **Unified metrics**: All KPIs from Project 1 mart
-  **Versioning**: Metric versioning and release tracking (`metric_release_log`)
-  **Quality gates**: dbt test failure → block release; Completeness failure → block
-  **Idempotency**: Reverse ETL safe to retry, no duplicates
-  **SLA**: API p95 < 300ms; KPI freshness < 10 min; Completeness = 100%
-  **Observability**: API latency, KPI freshness, Completeness, Reverse ETL success rate
-  **Deploy**: K8s Kustomize (dev/prod), config isolation (env vars)
-  **Governance**: Release log, version tracking, quality gates

---

## Project layout

### Root

- `README.md` — Main doc (architecture, quick start, layout)
- `Makefile` — One-command targets (dbt, API, Reverse ETL, demos)
- `.env.example` — Env config example

### analytics/

- `analytics/dbt/README.md` — dbt project doc
- `analytics/dbt/dbt_project.yml` — dbt config
- `analytics/dbt/profiles.yml` — Trino connection
- `analytics/dbt/packages.yml` — dbt deps
- `analytics/dbt/models/stg/stg_kpis_daily.sql` — Staging: KPI ref
- `analytics/dbt/models/stg/stg_users.sql` — Staging: users ref
- `analytics/dbt/models/stg/stg_orders.sql` — Staging: orders ref
- `analytics/dbt/models/stg/stg_payments.sql` — Staging: payments ref
- `analytics/dbt/models/int/int_user_segments.sql` — Intermediate: user segmentation
- `analytics/dbt/models/mart/mart_kpis_daily_v1.sql` — Mart: versioned KPI
- `analytics/dbt/models/mart/mart_user_segments.sql` — Mart: user segments
- `analytics/dbt/models/schema.yml` — Schema tests

### services/

- `services/metrics_api/README.md` — Metrics API doc
- `services/metrics_api/app/main.py` — FastAPI app
- `services/metrics_api/requirements.txt` — Python deps
- `services/metrics_api/Dockerfile` — Docker image

### reverse_etl/

- `reverse_etl/README.md` — Reverse ETL doc
- `reverse_etl/postgres/upsert_segments.py` — Postgres upsert
- `reverse_etl/kafka/publish_segments.py` — Kafka publish
- `reverse_etl/requirements.txt` — Python deps

### orchestration/

- `orchestration/airflow/dags/metric_publish_gate.py` — Quality gate DAG

### lakehouse/

- `lakehouse/ddl/metric_release_log.sql` — Release log DDL

### platform/

- `platform/k8s/README.md` — K8s deploy doc
- `platform/k8s/base/metrics-api-deployment.yaml` — Metrics API Deployment
- `platform/k8s/base/kustomization.yaml` — Kustomize base
- `platform/k8s/overlays/dev/kustomization.yaml` — Dev overlay
- `platform/k8s/overlays/prod/kustomization.yaml` — Prod overlay

### contracts/

- `contracts/metrics/kpis.yaml` — KPI contract
- `contracts/metrics/user_segments.yaml` — User segment contract
- `contracts/metrics/release_log.yaml` — Release log contract

### docs/

- `docs/architecture.md` — Architecture
- `docs/slo.md` — SLO
- `docs/release_process.md` — Release process
- `docs/tradeoffs.md` — Trade-offs
- `docs/acceptance_criteria.md` — Acceptance criteria

### runbook/

- `runbook/README.md` — Runbook index
- `runbook/release_process.md` — Release process
- `runbook/reverse_etl_failure.md` — Reverse ETL failures
- `runbook/api_latency.md` — API latency

### scripts/

- `scripts/setup.sh` — Setup
- `scripts/demo_metric_release.sh` — Metric release demo
- `scripts/demo_reverse_etl.sh` — Reverse ETL demo
- `scripts/demo_api_latency.sh` — API latency demo

### evidence/

- `evidence/README.md` — Evidence index
- `evidence/demos/` — Demo evidence
- `evidence/recon/` — Reconciliation evidence
- `evidence/releases/` — Release evidence
- `evidence/slo/` — SLO evidence

---

## References

### Core
- `docs/architecture.md` — Architecture
- `docs/slo.md` — SLO
- `docs/tradeoffs.md` — Trade-offs
- `docs/acceptance_criteria.md` — Acceptance criteria
- `docs/release_process.md` — Release process

### Runbooks
- `runbook/` — Incidents (release_process, reverse_etl_failure, api_latency)

### Components
- `analytics/dbt/README.md` — dbt
- `services/metrics_api/README.md` — Metrics API
- `reverse_etl/README.md` — Reverse ETL
- `platform/k8s/README.md` — K8s deploy

---

## Integration with Project 1

### Data
- **Direct ref**: Project 2 dbt queries Project 1 Gold
- **No copy**: Single source of truth
- **Version alignment**: Project 1 Gold changes flow to Project 2

### Shared infra
- **Trino**: Query engine (shared)
- **Iceberg catalog**: Same catalog, different schemas
- **Kafka** (optional): Reverse ETL can use same cluster
- **Postgres** (optional): Reverse ETL can use same DB

### Independence
- Project 2 can deploy independently
- dbt models self-contained
- API and Reverse ETL standalone

---

## Design principles

1. **Fully on Project 1**: No duplicate data, direct Gold refs
2. **Unified metrics**: All KPIs from same mart
3. **Versioning**: Metric versioning and release tracking
4. **Quality gates**: Test failure blocks release
5. **Idempotency**: Reverse ETL safe to retry
6. **Observability**: End-to-end monitoring and alerts

---

## License

Same as Project 1
