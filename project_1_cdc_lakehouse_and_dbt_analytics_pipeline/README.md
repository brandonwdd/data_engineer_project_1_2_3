# Project 1: Real-time CDC Lakehouse (Production-Grade Pipeline)

## 🚀 Status — v1.0 (Production-Ready)

- **v0.1** ✅: Local CDC infra (Postgres → Debezium → Kafka) + CDC contracts
- **v0.2** ✅: **Bronze ingest** — Spark Structured Streaming reads Debezium from Kafka, contract validation (fail-fast), writes to Iceberg `bronze.raw_cdc` (MinIO). Includes `event_uid`, `entity_key`, `ordering_key`, Kafka metadata, checkpoint recovery.
- **v0.3** ✅: **Silver layer** — Reads from Bronze, MERGE INTO by `ordering_key`, delete (op='d') support, idempotent. Tables: `silver.users`, `silver.orders`, `silver.payments`.
- **v0.4** ✅: **Gold layer (dbt)** — stg → int → mart; `dim_users`, `fct_orders`, `fct_payments`, `mart_kpis_daily`. dbt tests (not_null, unique, referential integrity, completeness).
- **v0.5** ✅: **Demo scripts** — `demo_failure_recovery.sh` (failure recovery), `demo_replay_idempotency.sh` (replay idempotency), `demo_schema_evolution.sh` (schema evolution).
- **v0.6** ✅: **Airflow DAGs** — `maintenance_iceberg.py` (compact, expire snapshots, remove orphans), `quality_gate_cdc.py` (dbt tests, block on failure), `reconciliation.py`, `backfill.py`.
- **v0.7** ✅: **Observability (Datadog)** — Monitors (consumer lag, freshness, completeness, job success), Dashboard (SLO-aligned).
- **v0.8** ✅: **K8s deploy** — Kustomize overlays (dev/stg/prod), one-command deploy (`make deploy-k8s-*`).

**~98% complete** (implementation 100%, Terraform + CI/CD done; remaining: runtime testing)

---

## 🛠️ Tech Stack

### Core components
- **PostgreSQL** 15+ — OLTP source (wal_level=logical)
- **Debezium** 2.x — CDC connector (Postgres Source)
- **Apache Kafka** 3.x — CDC event bus
- **Apache Spark** 3.5.0 — Streaming (Structured Streaming)
- **Apache Iceberg** 1.4.2 — Lakehouse format (time travel, MERGE)
- **dbt** — Modeling (stg → int → mart)
- **Trino** — SQL engine (dbt → Iceberg)
- **Apache Airflow** 2.x — Orchestration (maintenance, quality gate)
- **Datadog** — Observability (monitors, dashboard)
- **Kubernetes** + **Kustomize** — Orchestration (dev/stg/prod)

### Storage
- **MinIO** — S3-compatible (local dev)
- **AWS S3** — Production (Terraform)

### Languages
- **Python** 3.x — Spark jobs, tests
- **SQL** — Spark, Trino, dbt
- **YAML** — Contracts, K8s, Datadog
- **Bash** — Demos, reconciliation

### Tooling
- **Docker** + **Docker Compose** — Local dev
- **Terraform** — IaC (optional, AWS)
- **GitHub Actions** — CI/CD (placeholder)

See `docs/progress_report.md` for details.

---

## 📊 Data Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         OLTP source layer                               │
├─────────────────────────────────────────────────────────────────────────┤
│  infra/sql/project1.sql                                                 │
│  └─ Source tables: users, orders, payments                              │
│                                                                          │
│  Postgres (postgres)                                          │
│  └─ wal_level=logical, logical replication                             │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ INSERT/UPDATE/DELETE
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      CDC capture (Debezium)                             │
├─────────────────────────────────────────────────────────────────────────┤
│  connectors/debezium/configs/project_1_connector.json                    │
│  └─ Debezium Postgres Connector config                                  │
│     • database.hostname, topic.prefix, table.include.list               │
│     • snapshot.mode=initial, plugin.name=pgoutput                       │
│                                                                          │
│  Kafka Connect (kafka-connect)                                 │
│  └─ Debezium connector, WAL capture                                     │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Debezium Envelope (JSON)
                              │ {op, ts_ms, source, before, after}
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Message bus (Kafka)                             │
├─────────────────────────────────────────────────────────────────────────┤
│  Kafka Broker (kafka)                                         │
│  └─ Topics:                                                             │
│     • dbserver_docker.public.users                                       │
│     • dbserver_docker.public.orders                                      │
│     • dbserver_docker.public.payments                                    │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Spark Structured Streaming
                              │ (readStream from Kafka)
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Bronze parse & validate (Spark)                      │
├─────────────────────────────────────────────────────────────────────────┤
│  streaming/spark/bronze_ingest/ingest_raw_cdc.py                        │
│  └─ Entry: job.run()                                                    │
│                                                                          │
│  streaming/spark/bronze_ingest/job.py                                    │
│  └─ Main job:                                                           │
│     • build_spark() - SparkSession (Iceberg + S3/MinIO)                 │
│     • ensure_bronze_table() - create table if missing                   │
│     • readStream from Kafka                                             │
│     • mapInPandas() - parse + validate                                  │
│     • writeStream to Iceberg (checkpoint)                               │
│                                                                          │
│  streaming/spark/bronze_ingest/config.py                                │
│  └─ BronzeConfig: Kafka, Iceberg, S3/MinIO, checkpoint, contracts       │
│                                                                          │
│  streaming/spark/bronze_ingest/parse_debezium.py                        │
│  └─ Parse Debezium:                                                     │
│     • build_event_uid() - topic|partition|offset                        │
│     • parse_entity_key() - PK from key/after/before                     │
│     • parse_ordering_key() - lsn → updated_at → partition|offset        │
│     • parse_single() / parse_batch()                                    │
│                                                                          │
│  streaming/spark/bronze_ingest/contract_validate.py                    │
│  └─ Contract validation (fail-fast):                                    │
│     • load_contracts() - contracts/cdc/*.yaml                           │
│     • entity_from_topic() - topic → entity                              │
│     • validate_event() - op, ts_ms, source, after/before, PK            │
│                                                                          │
│  contracts/cdc/users.yaml, orders.yaml, payments.yaml                   │
│  └─ CDC contracts: PK, required fields, op, ordering_key, evolution     │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Append-only events
                              │ (event_uid, entity, entity_key, ordering_key,
                              │  kafka_*, op, ts_ms, source, before, after)
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Lakehouse storage (Iceberg + MinIO)                  │
├─────────────────────────────────────────────────────────────────────────┤
│  lakehouse/iceberg/ddl/bronze_raw_cdc.sql                               │
│  └─ Bronze table DDL (see docs)                                         │
│                                                                          │
│  MinIO (minio)                                                 │
│  └─ S3-compatible, bucket: warehouse                                    │
│     • s3a://warehouse/iceberg/ - Iceberg warehouse                      │
│     • s3a://warehouse/checkpoints/bronze/raw_cdc/ - Spark checkpoint    │
│                                                                          │
│  Iceberg Catalog: iceberg.bronze.raw_cdc                                │
│  └─ Schema:                                                             │
│     • event_uid, entity, entity_key, ordering_key                       │
│     • kafka_topic, kafka_partition, kafka_offset, kafka_timestamp       │
│     • op, ts_ms, source (JSON), before (JSON), after (JSON)             │
│     • ingest_time                                                         │
│     • Partition: days(ingest_time)                                       │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Batch read (Spark SQL)
                              │ (dedupe by entity_key, keep max ordering_key)
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Silver Merge Layer (Spark)                            │
├─────────────────────────────────────────────────────────────────────────┤
│  streaming/spark/silver_merge/merge_silver.py                            │
│  └─ Entry: call job.run()                                               │
│                                                                          │
│  streaming/spark/silver_merge/job.py                                    │
│  └─ Main job:                                                           │
│     • build_spark() - Create SparkSession (Iceberg + S3/MinIO)          │
│     • ensure_silver_tables() - Create Silver tables (users/orders/payments)│
│     • run_batch() - Read Bronze, group by entity                        │
│     • build_latest_events_df() - Get latest events by ordering_key (dedupe)│
│     • merge_entity() - MERGE INTO Silver (op='d' → DELETE, others → UPSERT)│
│                                                                          │
│  streaming/spark/silver_merge/config.py                                 │
│  └─ SilverConfig: Iceberg, S3/MinIO, checkpoint, contracts config      │
│                                                                          │
│  streaming/spark/silver_merge/parse_bronze.py                           │
│  └─ Parse Bronze events:                                                │
│     • build_latest_events_df() - Window function get latest (ROW_NUMBER) │
│     • parse_after_to_silver_row() - Extract fields from after JSON      │
│     • extract_entity_key_from_row() - Extract primary key value         │
│                                                                          │
│  lakehouse/iceberg/ddl/silver_{users,orders,payments}.sql              │
│  └─ Silver table DDL: entity tables (SCD1), partition days(_silver_updated_at)│
│                                                                          │
│  Iceberg Catalog: iceberg.silver.{users,orders,payments}               │
│  └─ Table structure: business fields + audit fields (_bronze_event_uid, _bronze_ordering_key)│
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ dbt run (Trino/Spark SQL)
                              │ (stg → int → mart)
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Gold Analytics Layer (dbt)                          │
├─────────────────────────────────────────────────────────────────────────┤
│  analytics/dbt/models/stg/stg_{users,orders,payments}.sql              │
│  └─ Staging: Read from Silver, type conversion, null handling, enum normalization│
│                                                                          │
│  analytics/dbt/models/int/int_{users,orders,payments}.sql               │
│  └─ Intermediate: Business logic layer (state machine, dedupe, filter deleted)│
│                                                                          │
│  analytics/dbt/models/mart/dim_users.sql                                │
│  analytics/dbt/models/mart/fct_orders.sql                            │
│  analytics/dbt/models/mart/fct_payments.sql                             │
│  analytics/dbt/models/mart/mart_kpis_daily.sql                          │
│  └─ Marts: Dimension tables, fact tables, KPI aggregation              │
│                                                                          │
│  analytics/dbt/models/schema.yml                                         │
│  └─ Schema tests：not_null, unique, relationships, accepted_values     │
│                                                                          │
│  analytics/dbt/tests/test_*.sql                                         │
│  └─ Custom tests: payments_amount_check, kpi_completeness               │
│                                                                          │
│  Iceberg Catalog: iceberg.{stg,int,mart}.*                              │
│  └─ dbt-generated tables/views (materialized: view/table)                │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Complete Data Flow (File Call Order)

### Phase 1: Infrastructure Initialization

**Step 1.1: Database Initialization**
- File: `infra/sql/project1.sql`
- Purpose: Define Postgres table structure (users, orders, payments)
- Execute: `docker exec -it postgres psql -U postgres -d project1 -f /tmp/project1.sql`
- Result: Postgres DB contains source tables, wal_level=logical

**Step 1.2: Debezium Connector Configuration**
- File: `connectors/debezium/configs/project_1_connector.json`
- Purpose: Configure Debezium Postgres Source Connector
- Execute: `curl -X POST http://localhost:8083/connectors -H "Content-Type: application/json" -d @connectors/debezium/configs/project_1_connector.json`
- Result: Kafka Connect runs Debezium connector, captures WAL changes

**Step 1.3: Kafka Topics Creation**
- File: Auto-created (by Debezium connector)
- Purpose: Create Kafka topics (dbserver_docker.public.{users,orders,payments})
- Result: CDC events published to Kafka

**Step 1.4: MinIO (and full stack for P2/P3)**
- File: `platform/local/docker-compose.yml`
- One command starts all: `cd platform/local && docker compose up -d` — Postgres, Kafka, Connect, MinIO, **Trino**, **Airflow** (so Project 2 and 3 can use the same stack). See `platform/local/README.md`.
- For Bronze only: `docker compose --profile bronze run --rm spark` (MinIO already up from `up -d`)
- Result: MinIO running, bucket `warehouse` created; Trino on 8080; Airflow UI on 8081

---

### Phase 2: Bronze Layer Data Ingestion

**Step 2.1: Start Bronze Ingest Job**
- File: `streaming/spark/bronze_ingest/ingest_raw_cdc.py`
- Purpose: Entry script, set PYTHONPATH, call `job.run()`
- Execute: `spark-submit streaming/spark/bronze_ingest/ingest_raw_cdc.py`
- Next: → `streaming/spark/bronze_ingest/job.py`

**Step 2.2: Load Configuration**
- File: `streaming/spark/bronze_ingest/job.py` → `streaming/spark/bronze_ingest/config.py`
- Purpose: Read config from env vars (Kafka, Iceberg, S3/MinIO, checkpoint, contracts)
- Method: `BronzeConfig.from_env()`
- Result: Config object (Kafka bootstrap/topics, Iceberg warehouse, S3 endpoint/credentials, checkpoint location, contracts dir)
- Next: → Create SparkSession

**Step 2.3: Create SparkSession**
- File: `streaming/spark/bronze_ingest/job.py` → `build_spark()`
- Purpose: Create SparkSession, configure Iceberg catalog, S3/MinIO connection
- Result: SparkSession configured, can connect to Kafka and Iceberg
- Next: → Ensure Bronze table exists

**Step 2.4: Create Bronze Table**
- File: `streaming/spark/bronze_ingest/job.py` → `ensure_bronze_table()` → `lakehouse/iceberg/ddl/bronze_raw_cdc.sql`
- Purpose: Execute DDL, create `iceberg.bronze.raw_cdc` table (if not exists)
- Result: Bronze table created, partition strategy `days(ingest_time)`
- Next: → Read stream from Kafka

**Step 2.5: Read Kafka Stream**
- File: `streaming/spark/bronze_ingest/job.py` → `readStream from Kafka`
- Purpose: Subscribe to Kafka topics (dbserver_docker.public.{users,orders,payments})
- Result: Spark Structured Streaming consumes Debezium events from Kafka
- Next: → Parse + validate

**Step 2.6: Parse Debezium Events**
- File: `streaming/spark/bronze_ingest/job.py` → `mapInPandas()` → `streaming/spark/bronze_ingest/parse_debezium.py`
- Purpose: Parse Debezium envelope, generate event_uid, entity_key, ordering_key
- Function call chain:
  1. `parse_batch()` → batch parse
  2. `parse_single()` → parse single event
  3. `build_event_uid()` → generate `topic|partition|offset`
  4. `parse_entity_key()` → extract primary key from key/after/before
  5. `parse_ordering_key()` → generate deterministic ordering key (lsn → updated_at → partition|offset)
- Next: → Contract validation

**Step 2.7: Contract Validation**
- File: `streaming/spark/bronze_ingest/parse_debezium.py` → `streaming/spark/bronze_ingest/contract_validate.py`
- Purpose: Validate events against contracts (fail-fast, quality first)
- Function call chain:
  1. `validate_event()` → validate event
  2. `load_contracts()` → load contracts (if not loaded)
  3. Read `contracts/cdc/{users,orders,payments}.yaml`
  4. `entity_from_topic()` → topic → entity mapping
  5. Validate: required fields (op, ts_ms, source), op validity (c/u/d/r), after/before rules, primary key extractable
- Result: Validation pass → return Bronze row (dict); validation fail → raise `ContractViolation` exception
- Next: → Write to Iceberg

**Step 2.8: Write to Bronze Table**
- File: `streaming/spark/bronze_ingest/job.py` → `writeStream.format("iceberg")`
- Purpose: Write to `iceberg.bronze.raw_cdc`, enable checkpoint
- Result: CDC events written to Bronze table, checkpoint saved at `s3a://warehouse/checkpoints/bronze/raw_cdc`
- Storage: MinIO (`s3a://warehouse/iceberg/`)

---

### Phase 3: Silver Layer Data Merge

**Step 3.1: Start Silver Merge Job**
- File: `streaming/spark/silver_merge/merge_silver.py`
- Purpose: Entry script, set PYTHONPATH, call `job.run()`
- Execute: `spark-submit streaming/spark/silver_merge/merge_silver.py`
- Next: → `streaming/spark/silver_merge/job.py`

**Step 3.2: Load Configuration**
- File: `streaming/spark/silver_merge/job.py` → `streaming/spark/silver_merge/config.py`
- Purpose: Read config from env vars (Iceberg, S3/MinIO, checkpoint)
- Method: `SilverConfig.from_env()`
- Result: Config object (Iceberg warehouse, S3 endpoint/credentials, checkpoint location, window duration)
- Next: → Create SparkSession

**Step 3.3: Create SparkSession**
- File: `streaming/spark/silver_merge/job.py` → `build_spark()`
- Purpose: Create SparkSession, configure Iceberg catalog, S3/MinIO connection
- Result: SparkSession configured, can connect to Iceberg
- Next: → Ensure Silver tables exist

**Step 3.4: Create Silver Tables**
- File: `streaming/spark/silver_merge/job.py` → `ensure_silver_tables()` → `lakehouse/iceberg/ddl/silver_{users,orders,payments}.sql`
- Purpose: Execute DDL, create `iceberg.silver.{users,orders,payments}` tables (if not exists)
- Result: Silver tables created, partition strategy `days(_silver_updated_at)`
- Next: → Read Bronze table

**Step 3.5: Read Bronze Table**
- File: `streaming/spark/silver_merge/job.py` → `run_batch()` → read `iceberg.bronze.raw_cdc`
- Purpose: Read all events from Bronze table
- Result: DataFrame contains all Bronze events
- Next: → Group by entity

**Step 3.6: Group by Entity**
- File: `streaming/spark/silver_merge/job.py` → `run_batch()` → call `merge_entity()` for each entity (users/orders/payments)
- Purpose: Process each entity's data separately
- Next: → Window function dedupe

**Step 3.7: Window Function Dedupe**
- File: `streaming/spark/silver_merge/job.py` → `streaming/spark/silver_merge/parse_bronze.py` → `build_latest_events_df()`
- Purpose: Group by `entity_key`, sort by `ordering_key` DESC, ROW_NUMBER take first (latest event)
- Result: Each `entity_key` keeps only the event with max `ordering_key`
- Next: → Separate deletes and upserts

**Step 3.8: Separate Deletes and Upserts**
- File: `streaming/spark/silver_merge/job.py` → `merge_entity()`
- Purpose: Separate `op='d'` (delete) and `op in ('c','u','r')` (upsert)
- Result: Two DataFrames (deletes_df, upserts_df)
- Next: → Process deletes

**Step 3.9: Process Deletes**
- File: `streaming/spark/silver_merge/job.py` → `merge_entity()` → DELETE logic
- Purpose: Extract primary key values from `before` JSON, execute `DELETE FROM table WHERE pk IN (...)`
- Result: Rows with corresponding primary keys deleted from Silver table
- Next: → Process upserts

**Step 3.10: Process Upserts**
- File: `streaming/spark/silver_merge/job.py` → `merge_entity()` → `streaming/spark/silver_merge/parse_bronze.py` → `parse_after_to_silver_row()`
- Purpose:
  1. Extract business fields from `after` JSON (using `from_json` + schema)
  2. Execute `MERGE INTO ... WHEN MATCHED AND source._bronze_ordering_key > target._bronze_ordering_key THEN UPDATE SET * WHEN NOT MATCHED THEN INSERT *`
- Result: Silver table updated (idempotent merge, based on `ordering_key` comparison)
- Storage: MinIO (`s3a://warehouse/iceberg/`)

---

### Phase 4: Gold Layer Data Analytics

**Step 4.1: Run dbt Models**
- File: `analytics/dbt/dbt_project.yml` (project config) → `dbt run`
- Purpose: Execute dbt models, read from Silver, generate Gold layer tables
- Config: `analytics/dbt/profiles.yml` (Trino/Iceberg connection)
- Next: → Staging layer

**Step 4.2: Staging Layer**
- File: `analytics/dbt/models/stg/stg_users.sql`, `stg_orders.sql`, `stg_payments.sql`
- Purpose: Read from `iceberg.silver.*`, type conversion (CAST), null handling, enum normalization
- Result: Staging views (materialized: view)
- Next: → Intermediate layer

**Step 4.3: Intermediate Layer**
- File: `analytics/dbt/models/int/int_users.sql`, `int_orders.sql`, `int_payments.sql`
- Purpose: Business logic layer (status normalization, state machine, filter deleted, amount validation)
- Result: Intermediate tables (materialized: table)
- Next: → Mart layer

**Step 4.4: Mart Layer**
- Files:
  - `analytics/dbt/models/mart/dim_users.sql` → User dimension table
  - `analytics/dbt/models/mart/fct_orders.sql` → Order fact table
  - `analytics/dbt/models/mart/fct_payments.sql` → Payment fact table
  - `analytics/dbt/models/mart/mart_kpis_daily.sql` → Daily KPI aggregation table
- Purpose: Generate dimension tables, fact tables, KPI aggregation
- Result: Mart tables (materialized: table)
- Next: → Data quality tests

**Step 4.5: Data Quality Tests**
- Files:
  - `analytics/dbt/models/schema.yml` → Schema tests (not_null, unique, relationships, accepted_values)
  - `analytics/dbt/tests/test_payments_amount_check.sql` → Payment amount validation
  - `analytics/dbt/tests/test_kpi_completeness.sql` → KPI partition completeness
- Purpose: Run `dbt test`, validate data quality
- Result: Tests pass → data available; tests fail → block release
- Storage: MinIO (`s3a://warehouse/iceberg/`)

---

### Phase 5: Orchestration and Operations

**Step 5.1: Iceberg Maintenance**
- File: `orchestration/airflow/dags/maintenance_iceberg.py`
- Purpose: Run Iceberg maintenance tasks daily
- Tasks:
  1. `compact_bronze_raw_cdc` → `CALL iceberg.system.rewrite_data_files('iceberg.bronze.raw_cdc', REWRITE_ALL)`
  2. `compact_silver_*` → Compact each Silver table
  3. `expire_snapshots` → `CALL iceberg.system.expire_snapshots(..., TIMESTAMP '7 days ago')`
  4. `remove_orphan_files` → `CALL iceberg.system.remove_orphan_files(...)`
- Result: Iceberg tables optimized, small files merged, expired snapshots cleaned

**Step 5.2: Quality Gate**
- File: `orchestration/airflow/dags/quality_gate_cdc.py`
- Purpose: Run quality gate hourly, validate data quality
- Tasks:
  1. `dbt_test` → Execute `dbt test --store-failures`
  2. `check_test_results` → Check test results, exit 1 on failure (block)
  3. `alert_on_failure` → Alert on failure
- Result: Quality gate passes → data can be released; fails → block downstream release

**Step 5.3: Reconciliation Job**
- File: `orchestration/airflow/dags/reconciliation.py` → `scripts/run_reconciliation.sh`
- Purpose: Run reconciliation every 6 hours, generate reconciliation reports
- Tasks:
  1. Query Bronze table counts, event_uid continuity
  2. Query Silver table counts, primary key uniqueness
  3. Query Gold table counts, KPI checksum
  4. Generate reconciliation report → `recon/YYYY-MM-DD_HHMMSS_recon_report.txt`
- Result: Reconciliation report generated, can be used to verify data consistency

**Step 5.4: Backfill Job**
- File: `orchestration/airflow/dags/backfill.py`
- Purpose: Manual trigger, re-run Silver/Gold
- Tasks:
  1. `backfill_silver` → Execute `spark-submit merge_silver.py` (re-run Silver)
  2. `backfill_gold` → Execute `dbt run` (re-run Gold)
- Result: Silver/Gold layer data recomputed

---

### Phase 6: Demo Script Validation

**Demo 1: Failure Recovery**
- File: `scripts/demo_failure_recovery.sh`
- Flow:
  1. Start Bronze ingest (background) → `streaming/spark/bronze_ingest/ingest_raw_cdc.py`
  2. Generate test data (Postgres INSERT)
  3. kill Bronze job
  4. Record pre-recovery state → `scripts/run_reconciliation.sh`
  5. Restart Bronze (recover from checkpoint) → `streaming/spark/bronze_ingest/ingest_raw_cdc.py`
  6. Run Silver merge → `streaming/spark/silver_merge/merge_silver.py`
  7. Record post-recovery state → `scripts/run_reconciliation.sh`
  8. Compare pre/post reports → `recon/` directory
- Result: Verify checkpoint recovery mechanism, no data loss

**Demo 2: Replay Idempotency**
- File: `scripts/demo_replay_idempotency.sh`
- Flow:
  1. Generate test data window
  2. Record initial KPI checksum (Run 1) → Query `iceberg.mart.mart_kpis_daily`
  3. Reset Kafka offsets (new consumer group)
  4. Re-run Bronze (replay) → `streaming/spark/bronze_ingest/ingest_raw_cdc.py`
  5. Re-run Silver (idempotent) → `streaming/spark/silver_merge/merge_silver.py`
  6. Record final KPI checksum (Run 2) → Query `iceberg.mart.mart_kpis_daily`
  7. Verify checksum unchanged
- Result: Verify idempotency, repeat processing same window, KPI checksum constant

**Demo 3: Schema Evolution**
- File: `scripts/demo_schema_evolution.sh`
- Flow:
  1. Record current schema (Postgres `\d`)
  2. ALTER TABLE ADD COLUMN (backward compatible: nullable) → Postgres
  3. INSERT data with new field → Postgres
  4. Verify Debezium captures new field → Kafka topic
  5. ALTER TABLE Silver ADD COLUMN (Iceberg) → `lakehouse/iceberg/ddl/silver_*.sql`
  6. Re-run Silver merge (handle new field) → `streaming/spark/silver_merge/merge_silver.py`
  7. Verify Silver table contains new column → `iceberg.silver.*`
- Result: Verify schema evolution process, backward compatible field addition

---

### Key Call Chain Summary

**1. Bronze Config Loading Chain**:
```
ingest_raw_cdc.py → job.py → config.py.from_env() → env vars → BronzeConfig
```

**2. Bronze Parsing and Validation Chain**:
```
job.py.mapInPandas() → parse_debezium.parse_batch() 
  → parse_debezium.parse_single() 
  → contract_validate.validate_event() 
  → contract_validate.load_contracts() 
  → contracts/cdc/{users,orders,payments}.yaml
```

**3. Bronze Storage Chain**:
```
job.py.writeStream() → Iceberg Catalog → MinIO (s3a://warehouse/iceberg/)
```

**4. Silver Merge Chain**:
```
merge_silver.py → job.py.run_batch() 
  → parse_bronze.build_latest_events_df() (window function dedupe)
  → job.py.merge_entity() 
  → Spark SQL MERGE INTO → Iceberg Catalog (silver.*)
```

**5. Gold Modeling Chain**:
```
dbt run → stg/{users,orders,payments}.sql (read from Silver)
  → int/{users,orders,payments}.sql (business logic)
  → mart/{dim_users,fct_orders,fct_payments,mart_kpis_daily}.sql (dimension/fact/KPI)
  → dbt test (schema.yml + tests/*.sql)
  → Iceberg Catalog (stg/int/mart.*)
```

---

## 🎯 Project Progress Details

### ✅ Completed (v0.2)

1. **Infrastructure**
   - ✅ Postgres + Kafka + Kafka Connect (Debezium) local stack
   - ✅ MinIO object storage (S3-compatible)
   - ✅ Docker Compose orchestration

2. **CDC Capture**
   - ✅ Debezium connector configuration and deployment
   - ✅ Kafka topics auto-created
   - ✅ CDC events end-to-end validation

3. **Data Contracts**
   - ✅ YAML contracts for three entities (users, orders, payments)
   - ✅ Primary keys, required fields, op semantics, ordering_key priority, evolution policy

4. **Bronze Ingest**
   - ✅ Spark Structured Streaming job
   - ✅ Debezium event parsing (event_uid, entity_key, ordering_key)
   - ✅ Contract validation (fail-fast)
   - ✅ Iceberg table creation and writes
   - ✅ Checkpoint recovery mechanism
   - ✅ Unit tests (16 tests all pass)

5. **Documentation**
   - ✅ README, command.md, architecture docs, SLO, tradeoffs

---

### 🚧 In Progress / Pending (v0.3+)

1. **Silver Layer**
   - 🚧 Read from Bronze, MERGE INTO by entity_key + ordering_key
   - 🚧 Delete handling (op='d' → DELETE)
   - 🚧 Idempotency validation

2. **Gold Layer**
   - 🚧 dbt models (stg → int → mart)
   - 🚧 Quality gates (dbt tests)
   - 🚧 KPI calculation

3. **Orchestration**
   - 🚧 Airflow DAGs (backfill, maintenance, quality gate, reconciliation)

4. **Observability**
   - 🚧 Datadog monitoring (consumer lag, freshness, completeness)
   - 🚧 Alert rules

5. **Demo Scripts**
   - 🚧 Demo-1 failure recovery
   - 🚧 Demo-2 replay idempotency
   - 🚧 Demo-3 schema evolution

6. **Operations**
   - 🚧 Runbook completion (incident handling procedures)
   - 🚧 CI/CD pipeline

---

## 🚀 Quick Start

### 1. Start / Reset Docker Environment

```bash
# Stop all containers started by docker-compose (keep volumes)
cd platform/local
docker compose down

# Restart all services in background
docker compose up -d

# For full reset (⚠ clears Kafka / Postgres persistent data)
docker compose down -v
docker compose up -d
```

### 2. Initialize Postgres Database

```bash
# Copy local SQL file into Postgres container
docker cp infra/sql/project1.sql postgres:/tmp/project1.sql

# Execute SQL script in container (create tables / insert data / create schema)
docker exec -it postgres psql -U postgres -d project1 -f /tmp/project1.sql

# List tables in public schema, verify table creation
docker exec -it postgres psql -U postgres -d project1 -c "\dt public.*"
```

### 3. Create Debezium Connector

```bash
# Submit new Debezium connector config to Kafka Connect REST API
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/debezium/configs/project_1_connector.json

# Check connector status
curl http://localhost:8083/connectors
curl http://localhost:8083/connectors/project-1-postgres-cdc-docker/status

# Restart connector if needed
curl -X POST http://localhost:8083/connectors/project-1-postgres-cdc-docker/restart
```

### 4. Check Kafka Topics Created

```bash
# List all topics, filter for dbserver_docker
docker exec -it kafka bash -lc "kafka-topics.sh --bootstrap-server localhost:9092 --list | grep dbserver_docker || true"
# Or use kafka-topics (some images use this command)
docker exec -it kafka sh -lc "kafka-topics --bootstrap-server localhost:9092 --list | grep dbserver_docker || true"
```

### 5. Verify Debezium CDC Working

```bash
# Consume 3 messages from Debezium topic to verify CDC
# --from-beginning: read from earliest offset
# --max-messages 3: read 3 and exit
docker exec -it kafka sh -lc "kafka-console-consumer --bootstrap-server localhost:9092 --topic dbserver_docker.public.orders --from-beginning --max-messages 3"
```

### 6. Start Bronze Ingest (Kafka → Iceberg raw_cdc)

**Prerequisites**: Postgres + Kafka + Connect + MinIO started, Connector created, tables and CDC validated.

```bash
# 1) Start Bronze services (MinIO + minio-init creates bucket warehouse)
cd platform/local
docker compose --profile bronze up -d
# Wait ~15s for minio-init to finish

# 2) Run Bronze streaming write (long-running, Ctrl+C to stop)
docker compose --profile bronze run --rm spark
```

Or use Makefile (in project root):

```bash
make bronze-up    # Start MinIO + init
make bronze-run   # Run Spark Bronze ingest
```

Spark consumes `dbserver_docker.public.{users,orders,payments}` from Kafka, parses Debezium events, contract validation (blocks on failure), writes to Iceberg `bronze.raw_cdc`, checkpoint at `s3a://warehouse/checkpoints/bronze/raw_cdc`.

### 7. Run Tests

#### 7.1 Unit Tests

```bash
pip install -r streaming/spark/requirements.txt
PYTHONPATH=. python -m pytest streaming/spark/tests -v
# Or
make test-bronze
```

**Expected**: 16 tests all pass ✅

#### 7.2 Acceptance Tests

```bash
# Run acceptance tests (validate all go-live criteria)
./scripts/test_acceptance.sh
# Or
make test-acceptance
```

**Output**: `evidence/validation/acceptance_test_report_YYYY-MM-DD_HHMMSS.md`

**Validates**:
- Unit tests pass
- Contract files exist
- Demo scripts exist
- K8s/Docker/Terraform configs exist
- Documentation completeness

#### 7.3 Idempotency Validation (Requires Runtime)

```bash
# Prerequisite: Ensure MinIO and Postgres running
cd platform/local
docker compose --profile bronze up -d

# Run idempotency test (default: repeat 3 times)
./scripts/test_idempotency.sh
# Or
make test-idempotency

# Specify repeat count
./scripts/test_idempotency.sh 5
```

**Output**: `evidence/validation/idempotency_test_YYYY-MM-DD_HHMMSS.md`

**Validates**: Repeat same data window N times, verify checksum unchanged

#### 7.4 Generate Test Evidence Package

```bash
./scripts/generate_test_evidence.sh
# Or
make test-evidence
```

**Output**: 
- Directory: `evidence/validation/test_evidence_YYYY-MM-DD_HHMMSS/`
- Archive: `evidence/validation/test_evidence_package_YYYY-MM-DD_HHMMSS.tar.gz`

**Contains**: Unit test reports, coverage, acceptance tests, idempotency tests, project structure snapshot

#### 7.5 Run All Tests

```bash
make test-all
```

See `evidence/validation/README.md` for details

### 8. Recommended Execution Order (One-Command Reset)

```bash
# 1) Reset environment
cd platform/local
docker compose down -v
docker compose up -d

# 2) Initialize database
docker cp infra/sql/project1.sql postgres:/tmp/project1.sql
docker exec -it postgres psql -U postgres -d project1 -f /tmp/project1.sql

# 3) Create Debezium Connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/debezium/configs/project_1_connector.json

# 4) Insert test data
docker exec -it postgres psql -U postgres -d project1 -c "
insert into public.users(user_id, email, status, created_at, updated_at)
values (1, 'u1@example.com', 'active', now(), now());

insert into public.orders(order_id, user_id, order_ts, status, total_amount, updated_at)
values (1, 1, now(), 'created', 123.45, now());

insert into public.payments(payment_id, order_id, amount, status, failure_reason, updated_at)
values (1, 1, 123.45, 'paid', null, now());
"

# 5) View topics + consume data
docker exec -it kafka sh -lc "kafka-topics --bootstrap-server kafka:9092 --list | grep dbserver_docker || true"
docker exec -it kafka sh -lc "kafka-console-consumer --bootstrap-server kafka:9092 --topic dbserver_docker.public.orders --from-beginning --max-messages 3"

# 6) Start Bronze Ingest
docker compose --profile bronze up -d
sleep 15  # Wait for minio-init to finish
docker compose --profile bronze run --rm spark
```

---

## 📈 Acceptance Criteria

- ✅ **Data correctness**: No data loss (event_uid continuity), controlled duplicates (idempotent design), eventual consistency
- ✅ **Replay/backfill**: Checkpoint recovery, Kafka offset replay (demo scripts implemented)
- ✅ **SLA**: P95 latency < 2 minutes (monitoring configured), completeness checks (dbt tests + reconciliation)
- ✅ **Observability**: End-to-end latency, consumer lag, job success rate, freshness, completeness (Datadog monitors + dashboard)
- ✅ **Deployability**: Docker Compose one-command start, K8s Kustomize deploy (dev/stg/prod), config isolation (env vars)
- ✅ **Governance**: Schema evolution process (defined in contracts, demo scripts implemented)

---

### Root Directory Files

- `README.md` — Main project doc, includes architecture, quick start, file structure
- `Makefile` — One-command scripts (Docker, K8s, tests, storage switching)
- `.gitignore` — Git ignore config (.env, .terraform, logs, etc.)

### Infrastructure Layer (infra/)

- `infra/sql/project1.sql` — Postgres DB init script (defines users, orders, payments table structure)
- `infra/terraform/README.md` — Terraform usage docs
- `infra/terraform/environments/local/main.tf` — Local env Terraform config (MinIO, placeholder)
- `infra/terraform/environments/local/variables.tf` — Local env variable definitions
- `infra/terraform/environments/local/outputs.tf` — Local env outputs (MinIO config)
- `infra/terraform/environments/local/terraform.tfvars.example` — Local env variable example
- `infra/terraform/environments/dev/main.tf` — Dev env Terraform config (optional AWS S3 or MinIO)
- `infra/terraform/environments/dev/variables.tf` — Dev env variable definitions
- `infra/terraform/environments/dev/outputs.tf` — Dev env outputs
- `infra/terraform/environments/dev/terraform.tfvars.example` — Dev env variable example
- `infra/terraform/environments/prod/main.tf` — Prod env Terraform config (AWS S3 + IAM)
- `infra/terraform/environments/prod/variables.tf` — Prod env variable definitions
- `infra/terraform/environments/prod/outputs.tf` — Prod env outputs (S3 bucket, IAM keys)
- `infra/terraform/environments/prod/terraform.tfvars.example` — Prod env variable example

### Platform Orchestration Layer (platform/)

- `platform/local/docker-compose.yml` — Docker Compose orchestration (Postgres, Kafka, Connect, MinIO, Spark)
- `platform/k8s/README.md` — K8s deployment docs
- `platform/k8s/base/namespace.yaml` — K8s Namespace definition (project1-cdc)
- `platform/k8s/base/configmap.yaml` — K8s ConfigMap (env var config)
- `platform/k8s/base/kustomization.yaml` — Kustomize base config
- `platform/k8s/base/spark-bronze-deployment.yaml` — Spark Bronze ingest K8s Deployment
- `platform/k8s/base/spark-silver-deployment.yaml` — Spark Silver merge K8s Deployment
- `platform/k8s/base/minio-deployment.yaml` — MinIO K8s Deployment + Service
- `platform/k8s/overlays/dev/kustomization.yaml` — Dev env Kustomize overlay
- `platform/k8s/overlays/dev/spark-bronze-patch.yaml` — Dev env Bronze resource patch
- `platform/k8s/overlays/dev/spark-silver-patch.yaml` — Dev env Silver resource patch
- `platform/k8s/overlays/stg/kustomization.yaml` — Staging env Kustomize overlay
- `platform/k8s/overlays/prod/kustomization.yaml` — Prod env Kustomize overlay
- `platform/k8s/overlays/prod/spark-bronze-patch.yaml` — Prod env Bronze resource patch
- `platform/k8s/overlays/prod/spark-silver-patch.yaml` — Prod env Silver resource patch

### CDC Connector Layer (connectors/)

- `connectors/debezium/configs/project_1_connector.json` — Debezium Postgres Source Connector config (local Docker env)
- `connectors/debezium/configs/project_1_connector_external.json` — Debezium external Postgres connector config (optional)

### Data Contract Layer (contracts/)

- `contracts/cdc/users.yaml` — Users entity CDC event contract (PK, required fields, ordering_key, evolution policy)
- `contracts/cdc/orders.yaml` — Orders entity CDC event contract
- `contracts/cdc/payments.yaml` — Payments entity CDC event contract

### Streaming Layer (streaming/)

- `streaming/__init__.py` — Python package marker
- `streaming/spark/__init__.py` — Spark package marker
- `streaming/spark/Dockerfile` — Spark runtime Docker image definition
- `streaming/spark/requirements.txt` — Python dependencies (PyYAML, pytest)
- `streaming/spark/bronze_ingest/__init__.py` — Bronze ingest package marker
- `streaming/spark/bronze_ingest/ingest_raw_cdc.py` — Bronze ingest entry script (spark-submit)
- `streaming/spark/bronze_ingest/job.py` — Bronze ingest main job logic (SparkSession, Kafka read, Iceberg write)
- `streaming/spark/bronze_ingest/config.py` — Bronze config management (read Kafka/Iceberg/S3/checkpoint from env vars)
- `streaming/spark/bronze_ingest/parse_debezium.py` — Debezium event parsing (event_uid, entity_key, ordering_key)
- `streaming/spark/bronze_ingest/contract_validate.py` — Contract validation logic (fail-fast, quality first)
- `streaming/spark/silver_merge/__init__.py` — Silver merge package marker
- `streaming/spark/silver_merge/merge_silver.py` — Silver merge entry script (spark-submit)
- `streaming/spark/silver_merge/job.py` — Silver merge main job logic (read Bronze, MERGE INTO Silver)
- `streaming/spark/silver_merge/config.py` — Silver config management (read Iceberg/S3/checkpoint from env vars)
- `streaming/spark/silver_merge/parse_bronze.py` — Bronze event parsing (window function dedupe, extract Silver rows)
- `streaming/spark/tests/__init__.py` — Test package marker
- `streaming/spark/tests/test_contract_validate.py` — Contract validation unit tests
- `streaming/spark/tests/test_parse_debezium.py` — Debezium parsing logic unit tests
- `streaming/spark/tests/fixtures/users_cdc_key.json` — Test data: Users CDC key
- `streaming/spark/tests/fixtures/users_cdc_value.json` — Test data: Users CDC value
- `streaming/spark/tests/fixtures/users_insert.json` — Test data: Users insert event
- `streaming/spark/tests/fixtures/orders_delete_value.json` — Test data: Orders delete event

### Lakehouse Storage Layer (lakehouse/)

- `lakehouse/iceberg/README.md` — Iceberg usage docs
- `lakehouse/iceberg/ddl/bronze_raw_cdc.sql` — Bronze table DDL (reference)
- `lakehouse/iceberg/ddl/silver_users.sql` — Silver users table DDL
- `lakehouse/iceberg/ddl/silver_orders.sql` — Silver orders table DDL
- `lakehouse/iceberg/ddl/silver_payments.sql` — Silver payments table DDL

### Analytics Layer (analytics/)

- `analytics/dbt/README.md` — dbt project docs
- `analytics/dbt/dbt_project.yml` — dbt project config (model-paths, materialized strategy)
- `analytics/dbt/profiles.yml` — dbt connection config (Trino/Iceberg)
- `analytics/dbt/packages.yml` — dbt package dependencies (dbt_utils, dbt_expectations)
- `analytics/dbt/models/stg/stg_users.sql` — Staging layer: Users model (type conversion, null handling)
- `analytics/dbt/models/stg/stg_orders.sql` — Staging layer: Orders model
- `analytics/dbt/models/stg/stg_payments.sql` — Staging layer: Payments model
- `analytics/dbt/models/int/int_users.sql` — Intermediate layer: Users business logic (status normalization, filter deleted)
- `analytics/dbt/models/int/int_orders.sql` — Intermediate layer: Orders business logic (state machine, amount validation)
- `analytics/dbt/models/int/int_payments.sql` — Intermediate layer: Payments business logic (status normalization, amount validation)
- `analytics/dbt/models/mart/dim_users.sql` — Mart layer: User dimension table
- `analytics/dbt/models/mart/fct_orders.sql` — Mart layer: Order fact table
- `analytics/dbt/models/mart/fct_payments.sql` — Mart layer: Payment fact table
- `analytics/dbt/models/mart/mart_kpis_daily.sql` — Mart layer: Daily KPI aggregation table
- `analytics/dbt/models/schema.yml` — Schema tests definition (not_null, unique, relationships, accepted_values)
- `analytics/dbt/tests/test_payments_amount_check.sql` — Custom test: Payment amount validation
- `analytics/dbt/tests/test_kpi_completeness.sql` — Custom test: KPI partition completeness

### Orchestration Layer (orchestration/)

- `orchestration/airflow/dags/maintenance_iceberg.py` — Airflow DAG: Iceberg maintenance (compact, expire snapshots, remove orphans)
- `orchestration/airflow/dags/quality_gate_cdc.py` — Airflow DAG: Quality gate (dbt tests, block on failure)
- `orchestration/airflow/dags/reconciliation.py` — Airflow DAG: Reconciliation job (generate reconciliation reports)
- `orchestration/airflow/dags/backfill.py` — Airflow DAG: Backfill job (manual trigger, re-run Silver/Gold)

### Observability Layer (observability/)

- `observability/README.md` — Observability docs
- `observability/monitors/datadog/monitors.yaml` — Datadog monitor rules (as code)
- `observability/monitors/datadog/monitors.placeholder.yaml` — Datadog monitor placeholder
- `observability/dashboards/exports/dashboard.json` — Datadog Dashboard config (JSON)
- `observability/dashboards/exports/dashboard.placeholder.json` — Datadog Dashboard placeholder

### Documentation Layer (docs/)

- `docs/acceptance_criteria.md` — Acceptance criteria doc
- `docs/architecture.md` — Architecture design doc
- `docs/pending_items.md` — Pending items details
- `docs/postmortem_sample.md` — Postmortem example
- `docs/postmortem_template.md` — Postmortem template
- `docs/progress_report.md` — Project progress and tech stack list
- `docs/quick_start_terraform_ci.md` — Terraform + GitHub Actions quick start
- `docs/replay_and_backfill.md` — Replay and backfill strategy doc
- `docs/runbook.md` — Operations runbook
- `docs/slo.md` — Service Level Objectives (SLO) definitions
- `docs/terraform_explained.md` — Terraform IaC explained
- `docs/terraform_switch_guide.md` — Terraform output → Spark config switch guide
- `docs/tradeoffs.md` — Architecture tradeoffs

### Runbook Layer (runbook/)

- `runbook/README.md` — Runbook directory
- `runbook/data_quality_failure.md` — Data quality failure handling
- `runbook/job_failure.md` — Job failure handling
- `runbook/lag.md` — Consumer lag handling
- `runbook/replay_backfill.md` — Replay and backfill procedures
- `runbook/rollback.md` — Rollback procedures
- `runbook/schema_change.md` — Schema change handling

### Scripts Layer (scripts/)

- `scripts/demo_failure_recovery.sh` — Demo script: failure recovery (kill job → recover → reconcile)
- `scripts/demo_replay_idempotency.sh` — Demo script: replay idempotency (reset offsets → re-run → checksum unchanged)
- `scripts/demo_schema_evolution.sh` — Demo script: schema evolution (add field → end-to-end compatible)
- `scripts/run_reconciliation.sh` — Reconciliation script (generate Bronze/Silver/Gold reconciliation reports)
- `scripts/switch_to_s3.sh` — Switch to AWS S3 config script (from Terraform output)
- `scripts/switch_to_minio.sh` — Switch back to MinIO config script

### Reconciliation Reports Layer (recon/)

- `recon/README.md` — Reconciliation directory
- `recon/2026-01-15_demo1_bronze_silver_counts.csv` — Demo1 reconciliation: Bronze/Silver row count comparison
- `recon/2026-01-15_demo1_gold_kpi_checksum.txt` — Demo1 reconciliation: Gold KPI checksum
- `recon/2026-01-16_demo2_replay_comparison.csv` — Demo2 reconciliation: replay comparison
- `recon/latest_demo_summary.md` — Latest demo summary
- `recon/RECON_REPORT_TEMPLATE.md` — Reconciliation report template

### Evidence Directory Layer (evidence/)

- `evidence/README.md` — Evidence directory
- `evidence/demos/README.md` — Demo evidence directory
- `evidence/demos/demo_1_failure_recovery.md` — Demo1 evidence: failure recovery
- `evidence/demos/demo_2_replay_backfill.md` — Demo2 evidence: replay backfill
- `evidence/demos/demo_3_schema_evolution.md` — Demo3 evidence: schema evolution
- `evidence/postmortems/README.md` — Postmortem directory
- `evidence/recon/README.md` — Reconciliation evidence directory
- `evidence/releases/README.md` — Release evidence directory
- `evidence/slo/README.md` — SLO evidence directory
- `evidence/slo/slo_dashboard.placeholder.png` — SLO Dashboard screenshot placeholder
- `evidence/validation/README.md` — Validation evidence directory
- `evidence/validation/idempotency_check.md` — Idempotency validation evidence

### CI/CD Layer (.github/)

- `.github/README.md` — CI/CD docs
- `.github/workflows/ci.yml` — GitHub Actions CI workflow (lint, tests, dbt, terraform)
- `.github/workflows/README.md` — Workflow docs

---

## 📚 References

### Core Docs
- `docs/progress_report.md` — Project progress and tech stack list
- `docs/pending_items.md` — Pending items details
- `docs/architecture.md` — Architecture design
- `docs/slo.md` — Service Level Objectives
- `docs/tradeoffs.md` — Architecture tradeoffs
- `docs/acceptance_criteria.md` — Acceptance criteria

### Operations Docs
- `docs/runbook.md` — Operations runbook
- `runbook/` — Incident handling (lag, job_failure, data_quality_failure, schema_change, rollback, replay_backfill)
- `docs/replay_and_backfill.md` — Replay and backfill strategy
- `docs/postmortem_template.md` — Postmortem template

### Infrastructure Docs
- `infra/terraform/README.md` — Terraform usage
- `docs/terraform_explained.md` — Terraform IaC explained
- `docs/terraform_switch_guide.md` — MinIO/S3 switching guide
- `docs/quick_start_terraform_ci.md` — Terraform + GitHub Actions quick start

### Component Docs
- `lakehouse/iceberg/README.md` — Iceberg usage
- `analytics/dbt/README.md` — dbt project docs
- `platform/k8s/README.md` — K8s deployment docs
- `observability/README.md` — Observability docs
- `.github/README.md` — CI/CD docs

---

## 📁 Project File List

### Root Directory Files

- `README.md` — Main project doc, includes architecture, quick start, file structure
- `Makefile` — One-command scripts (Docker, K8s, tests, storage switching)
- `.gitignore` — Git ignore config (.env, .terraform, logs, etc.)

### Infrastructure Layer (infra/)

- `infra/sql/project1.sql` — Postgres DB init script (defines users, orders, payments table structure)
- `infra/terraform/README.md` — Terraform usage docs
- `infra/terraform/environments/local/main.tf` — Local env Terraform config (MinIO, placeholder)
- `infra/terraform/environments/local/variables.tf` — Local env variable definitions
- `infra/terraform/environments/local/outputs.tf` — Local env outputs (MinIO config)
- `infra/terraform/environments/local/terraform.tfvars.example` — Local env variable example
- `infra/terraform/environments/dev/main.tf` — Dev env Terraform config (optional AWS S3 or MinIO)
- `infra/terraform/environments/dev/variables.tf` — Dev env variable definitions
- `infra/terraform/environments/dev/outputs.tf` — Dev env outputs
- `infra/terraform/environments/dev/terraform.tfvars.example` — Dev env variable example
- `infra/terraform/environments/prod/main.tf` — Prod env Terraform config (AWS S3 + IAM)
- `infra/terraform/environments/prod/variables.tf` — Prod env variable definitions
- `infra/terraform/environments/prod/outputs.tf` — Prod env outputs (S3 bucket, IAM keys)
- `infra/terraform/environments/prod/terraform.tfvars.example` — Prod env variable example

### Platform Orchestration Layer (platform/)

- `platform/local/docker-compose.yml` — Docker Compose orchestration (Postgres, Kafka, Connect, MinIO, Spark)
- `platform/k8s/README.md` — K8s deployment docs
- `platform/k8s/base/namespace.yaml` — K8s Namespace definition (project1-cdc)
- `platform/k8s/base/configmap.yaml` — K8s ConfigMap (env var config)
- `platform/k8s/base/kustomization.yaml` — Kustomize base config
- `platform/k8s/base/spark-bronze-deployment.yaml` — Spark Bronze ingest K8s Deployment
- `platform/k8s/base/spark-silver-deployment.yaml` — Spark Silver merge K8s Deployment
- `platform/k8s/base/minio-deployment.yaml` — MinIO K8s Deployment + Service
- `platform/k8s/overlays/dev/kustomization.yaml` — Dev env Kustomize overlay
- `platform/k8s/overlays/dev/spark-bronze-patch.yaml` — Dev env Bronze resource patch
- `platform/k8s/overlays/dev/spark-silver-patch.yaml` — Dev env Silver resource patch
- `platform/k8s/overlays/stg/kustomization.yaml` — Staging env Kustomize overlay
- `platform/k8s/overlays/prod/kustomization.yaml` — Prod env Kustomize overlay
- `platform/k8s/overlays/prod/spark-bronze-patch.yaml` — Prod env Bronze resource patch
- `platform/k8s/overlays/prod/spark-silver-patch.yaml` — Prod env Silver resource patch

### CDC Connector Layer (connectors/)

- `connectors/debezium/configs/project_1_connector.json` — Debezium Postgres Source Connector config (local Docker env)
- `connectors/debezium/configs/project_1_connector_external.json` — Debezium external Postgres connector config (optional)

### Data Contract Layer (contracts/)

- `contracts/cdc/users.yaml` — Users entity CDC event contract (PK, required fields, ordering_key, evolution policy)
- `contracts/cdc/orders.yaml` — Orders entity CDC event contract
- `contracts/cdc/payments.yaml` — Payments entity CDC event contract

### Streaming Layer (streaming/)

- `streaming/__init__.py` — Python package marker
- `streaming/spark/__init__.py` — Spark package marker
- `streaming/spark/Dockerfile` — Spark runtime Docker image definition
- `streaming/spark/requirements.txt` — Python dependencies (PyYAML, pytest)
- `streaming/spark/bronze_ingest/__init__.py` — Bronze ingest package marker
- `streaming/spark/bronze_ingest/ingest_raw_cdc.py` — Bronze ingest entry script (spark-submit)
- `streaming/spark/bronze_ingest/job.py` — Bronze ingest main job logic (SparkSession, Kafka read, Iceberg write)
- `streaming/spark/bronze_ingest/config.py` — Bronze config management (read Kafka/Iceberg/S3/checkpoint from env vars)
- `streaming/spark/bronze_ingest/parse_debezium.py` — Debezium event parsing (event_uid, entity_key, ordering_key)
- `streaming/spark/bronze_ingest/contract_validate.py` — Contract validation logic (fail-fast, quality first)
- `streaming/spark/silver_merge/__init__.py` — Silver merge package marker
- `streaming/spark/silver_merge/merge_silver.py` — Silver merge entry script (spark-submit)
- `streaming/spark/silver_merge/job.py` — Silver merge main job logic (read Bronze, MERGE INTO Silver)
- `streaming/spark/silver_merge/config.py` — Silver config management (read Iceberg/S3/checkpoint from env vars)
- `streaming/spark/silver_merge/parse_bronze.py` — Bronze event parsing (window function dedupe, extract Silver rows)
- `streaming/spark/tests/__init__.py` — Test package marker
- `streaming/spark/tests/test_contract_validate.py` — Contract validation unit tests
- `streaming/spark/tests/test_parse_debezium.py` — Debezium parsing logic unit tests
- `streaming/spark/tests/fixtures/users_cdc_key.json` — Test data: Users CDC key
- `streaming/spark/tests/fixtures/users_cdc_value.json` — Test data: Users CDC value
- `streaming/spark/tests/fixtures/users_insert.json` — Test data: Users insert event
- `streaming/spark/tests/fixtures/orders_delete_value.json` — Test data: Orders delete event

### Lakehouse Storage Layer (lakehouse/)

- `lakehouse/iceberg/README.md` — Iceberg usage docs
- `lakehouse/iceberg/ddl/bronze_raw_cdc.sql` — Bronze table DDL (reference)
- `lakehouse/iceberg/ddl/silver_users.sql` — Silver users table DDL
- `lakehouse/iceberg/ddl/silver_orders.sql` — Silver orders table DDL
- `lakehouse/iceberg/ddl/silver_payments.sql` — Silver payments table DDL

### Analytics Layer (analytics/)

- `analytics/dbt/README.md` — dbt project docs
- `analytics/dbt/dbt_project.yml` — dbt project config (model-paths, materialized strategy)
- `analytics/dbt/profiles.yml` — dbt connection config (Trino/Iceberg)
- `analytics/dbt/packages.yml` — dbt package dependencies (dbt_utils, dbt_expectations)
- `analytics/dbt/models/stg/stg_users.sql` — Staging layer: Users model (type conversion, null handling)
- `analytics/dbt/models/stg/stg_orders.sql` — Staging layer: Orders model
- `analytics/dbt/models/stg/stg_payments.sql` — Staging layer: Payments model
- `analytics/dbt/models/int/int_users.sql` — Intermediate layer: Users business logic (status normalization, filter deleted)
- `analytics/dbt/models/int/int_orders.sql` — Intermediate layer: Orders business logic (state machine, amount validation)
- `analytics/dbt/models/int/int_payments.sql` — Intermediate layer: Payments business logic (status normalization, amount validation)
- `analytics/dbt/models/mart/dim_users.sql` — Mart layer: User dimension table
- `analytics/dbt/models/mart/fct_orders.sql` — Mart layer: Order fact table
- `analytics/dbt/models/mart/fct_payments.sql` — Mart layer: Payment fact table
- `analytics/dbt/models/mart/mart_kpis_daily.sql` — Mart layer: Daily KPI aggregation table
- `analytics/dbt/models/schema.yml` — Schema tests definition (not_null, unique, relationships, accepted_values)
- `analytics/dbt/tests/test_payments_amount_check.sql` — Custom test: Payment amount validation
- `analytics/dbt/tests/test_kpi_completeness.sql` — Custom test: KPI partition completeness

### Orchestration Layer (orchestration/)

- `orchestration/airflow/dags/maintenance_iceberg.py` — Airflow DAG: Iceberg maintenance (compact, expire snapshots, remove orphans)
- `orchestration/airflow/dags/quality_gate_cdc.py` — Airflow DAG: Quality gate (dbt tests, block on failure)
- `orchestration/airflow/dags/reconciliation.py` — Airflow DAG: Reconciliation job (generate reconciliation reports)
- `orchestration/airflow/dags/backfill.py` — Airflow DAG: Backfill job (manual trigger, re-run Silver/Gold)

### Observability Layer (observability/)

- `observability/README.md` — Observability docs
- `observability/monitors/datadog/monitors.yaml` — Datadog monitor rules (as code)
- `observability/monitors/datadog/monitors.placeholder.yaml` — Datadog monitor placeholder
- `observability/dashboards/exports/dashboard.json` — Datadog Dashboard config (JSON)
- `observability/dashboards/exports/dashboard.placeholder.json` — Datadog Dashboard placeholder

### Documentation Layer (docs/)

- `docs/acceptance_criteria.md` — Acceptance criteria doc
- `docs/architecture.md` — Architecture design doc
- `docs/pending_items.md` — Pending items details
- `docs/postmortem_sample.md` — Postmortem example
- `docs/postmortem_template.md` — Postmortem template
- `docs/progress_report.md` — Project progress and tech stack list
- `docs/quick_start_terraform_ci.md` — Terraform + GitHub Actions quick start
- `docs/replay_and_backfill.md` — Replay and backfill strategy doc
- `docs/runbook.md` — Operations runbook
- `docs/slo.md` — Service Level Objectives (SLO) definitions
- `docs/terraform_explained.md` — Terraform IaC explained
- `docs/terraform_switch_guide.md` — Terraform output → Spark config switch guide
- `docs/tradeoffs.md` — Architecture tradeoffs

### Runbook Layer (runbook/)

- `runbook/README.md` — Runbook directory
- `runbook/data_quality_failure.md` — Data quality failure handling
- `runbook/job_failure.md` — Job failure handling
- `runbook/lag.md` — Consumer lag handling
- `runbook/replay_backfill.md` — Replay and backfill procedures
- `runbook/rollback.md` — Rollback procedures
- `runbook/schema_change.md` — Schema change handling

### Scripts Layer (scripts/)

- `scripts/demo_failure_recovery.sh` — Demo script: failure recovery (kill job → recover → reconcile)
- `scripts/demo_replay_idempotency.sh` — Demo script: replay idempotency (reset offsets → re-run → checksum unchanged)
- `scripts/demo_schema_evolution.sh` — Demo script: schema evolution (add field → end-to-end compatible)
- `scripts/run_reconciliation.sh` — Reconciliation script (generate Bronze/Silver/Gold reconciliation reports)
- `scripts/switch_to_s3.sh` — Switch to AWS S3 config script (from Terraform output)
- `scripts/switch_to_minio.sh` — Switch back to MinIO config script

### Reconciliation Reports Layer (recon/)

- `recon/README.md` — Reconciliation directory
- `recon/2026-01-15_demo1_bronze_silver_counts.csv` — Demo1 reconciliation: Bronze/Silver row count comparison
- `recon/2026-01-15_demo1_gold_kpi_checksum.txt` — Demo1 reconciliation: Gold KPI checksum
- `recon/2026-01-16_demo2_replay_comparison.csv` — Demo2 reconciliation: replay comparison
- `recon/latest_demo_summary.md` — Latest demo summary
- `recon/RECON_REPORT_TEMPLATE.md` — Reconciliation report template

### Evidence Directory Layer (evidence/)

- `evidence/README.md` — Evidence directory
- `evidence/demos/README.md` — Demo evidence directory
- `evidence/demos/demo_1_failure_recovery.md` — Demo1 evidence: failure recovery
- `evidence/demos/demo_2_replay_backfill.md` — Demo2 evidence: replay backfill
- `evidence/demos/demo_3_schema_evolution.md` — Demo3 evidence: schema evolution
- `evidence/postmortems/README.md` — Postmortem directory
- `evidence/recon/README.md` — Reconciliation evidence directory
- `evidence/releases/README.md` — Release evidence directory
- `evidence/slo/README.md` — SLO evidence directory
- `evidence/slo/slo_dashboard.placeholder.png` — SLO Dashboard screenshot placeholder
- `evidence/validation/README.md` — Validation evidence directory
- `evidence/validation/idempotency_check.md` — Idempotency validation evidence

### CI/CD Layer (.github/)

- `.github/README.md` — CI/CD docs
- `.github/workflows/ci.yml` — GitHub Actions CI workflow (lint, tests, dbt, terraform)
- `.github/workflows/README.md` — Workflow docs
