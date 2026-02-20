# Architecture Overview

## High-Level Flow

```
Project 1 Gold marts (Iceberg) 
    ↓
Trino (Query Engine)
    ↓
┌─────────────────────────────────────┐
│  Project 2: Metrics Service          │
├─────────────────────────────────────┤
│  • dbt (semantic layer)              │
│  • Metrics API (FastAPI + Trino)    │
│  • Reverse ETL (Postgres + Kafka)   │
│  • Quality Gates (Airflow)          │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│  Activation Layer                    │
├─────────────────────────────────────┤
│  • Postgres (CRM/Ops systems)        │
│  • Kafka (Real-time activation)     │
└─────────────────────────────────────┘
```

## Components

### 1. dbt Semantic Layer

**Location**: `analytics/dbt/`

**Purpose**: Lightweight semantic layer that references Project 1's Gold tables

**Structure**:
- `stg/`: Direct references to Project 1 Gold tables
  - `stg_kpis_daily` → `iceberg.mart.mart_kpis_daily`
  - `stg_users` → `iceberg.mart.dim_users`
  - `stg_orders` → `iceberg.mart.fct_orders`
  - `stg_payments` → `iceberg.mart.fct_payments`
- `int/`: Business logic layer
  - `int_user_segments`: User segmentation calculations
- `mart/`: Final marts
  - `mart_kpis_daily_v1`: Versioned KPI mart
  - `mart_user_segments`: User segmentation mart

**Key Design Decisions**:
- **No data duplication**: Direct references to Project 1 tables
- **Versioning**: `mart_kpis_daily_v1` for version semantics
- **Single source of truth**: All KPIs come from Project 1's `mart_kpis_daily`

### 2. Metrics API

**Location**: `services/metrics_api/`

**Technology**: FastAPI + Trino

**Endpoints**:
- `GET /health`: Health check
- `GET /kpi?date=YYYY-MM-DD&version=v1`: Get daily KPIs
- `GET /kpi/range?start_date=...&end_date=...&version=v1`: Get KPI range
- `GET /user_segment?segment=...&date=...&version=v1`: Get users in segment
- `GET /versions`: List available metric versions
- `GET /metrics/list?version=v1`: List available metrics

**Features**:
- Versioned queries (via `version` parameter)
- Query timeout (30s default)
- Error handling and logging
- Direct Trino queries to Iceberg tables

**Caching** (Future):
- TTL-based caching for date-based queries
- Cache key: `{endpoint}_{date}_{version}`

### 3. Reverse ETL

**Location**: `reverse_etl/`

**Two Paths**:

#### 3.1 Postgres Upsert
**File**: `postgres/upsert_segments.py`

**Target Table**: `customer_segments`
- Primary key: `(user_id, segment_date)`
- Idempotent upsert via `ON CONFLICT`
- Tracks `source_run_id` for audit

**Semantics**:
- At-least-once delivery
- Idempotent (safe to retry)
- Per-user updates are atomic

#### 3.2 Kafka Publish
**File**: `kafka/publish_segments.py`

**Target Topic**: `segment_updates`
- Key: `user_id` (preserves per-user ordering)
- Value: JSON with segment data + metadata

**Semantics**:
- Keyed by `user_id` for ordering
- At-least-once delivery
- Idempotent producer enabled

### 4. Quality Gates (Airflow)

**Location**: `orchestration/airflow/dags/metric_publish_gate.py`

**Flow**:
1. **Run dbt tests**: Validate data quality
2. **Check completeness**: Verify expected partitions exist
3. **Insert release log**: Record release metadata
4. **Publish Reverse ETL**: Execute Postgres + Kafka writes

**Blocking Behavior**:
- If dbt tests fail → DAG fails, publishing blocked
- If completeness fails → DAG fails, publishing blocked
- Release log entry created only on success

### 5. Metric Release Log

**Location**: `lakehouse/ddl/metric_release_log.sql`

**Purpose**: Track metric version releases for governance

**Schema**:
- `release_id`: Unique release identifier
- `metric_version`: Version (v1, v2, ...)
- `git_commit`, `git_branch`: Source control tracking
- `released_by`, `released_at`: Release metadata
- `dbt_tests_passed`, `completeness_check_passed`: Quality gate results
- `data_range_start`, `data_range_end`: Data coverage
- `release_notes`: Human-readable notes

**Partitioning**: By `metric_version`

## Integration with Project 1

### Data Flow
1. Project 1 produces Gold marts in Iceberg (`mart_kpis_daily`, `dim_users`, etc.)
2. Project 2's dbt references these tables directly (no ETL)
3. Metrics API queries via Trino
4. Reverse ETL reads from Project 2's marts (which reference Project 1)

### Shared Infrastructure
- **Trino**: Query engine (shared)
- **Iceberg Catalog**: Same catalog, different schemas
- **Kafka**: Optional (if Reverse ETL uses same cluster)
- **Postgres**: Optional (if Reverse ETL writes to same DB)

### Independence
- Project 2 can be deployed independently
- dbt models are self-contained
- API service is standalone
- Reverse ETL scripts are standalone

## Data Quality & Governance

### Quality Gates
1. **dbt tests**: not_null, unique, referential integrity, accepted_values
2. **Completeness**: Expected partitions must exist
3. **Sanity checks**: `captured_amount <= total_gmv` (custom test)

### Versioning Strategy
- **Current**: v1 (hardcoded in models)
- **Future**: v2 models can coexist, API routes to correct version
- **Release log**: Tracks all version releases

### Observability
- API latency (p95 < 300ms target)
- KPI freshness (< 10 minutes target)
- Completeness (100% target)
- Reverse ETL success rate (> 99% target)

## Deployment

### Local Development
- Metrics API: `uvicorn app.main:app --host 0.0.0.0 --port 8000`
- Reverse ETL: Python scripts
- Airflow: Local scheduler

### Kubernetes (Future)
- Metrics API: Deployment + Service
- Reverse ETL: CronJob or Airflow tasks
- ConfigMaps for environment-specific configs
