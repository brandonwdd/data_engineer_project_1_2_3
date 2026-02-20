# dbt Project (Project 2)

## Overview

Project 2’s dbt project is a lightweight semantic layer. It references Project 1 Gold tables directly; no data copy.

## Structure

```
analytics/dbt/
├── dbt_project.yml          # dbt config
├── profiles.yml             # Trino connection
├── packages.yml             # dbt deps
├── models/
│   ├── stg/                 # Staging: direct ref to Project 1 Gold
│   ├── int/                 # Intermediate: business logic
│   └── mart/                # Mart: final marts
├── schema.yml               # Schema tests
└── tests/                   # Custom tests
```

## Layers

### Staging (stg/)

Direct refs to Project 1 Gold; no transforms:

- `stg_kpis_daily` → `iceberg.mart.mart_kpis_daily`
- `stg_users` → `iceberg.mart.dim_users`
- `stg_orders` → `iceberg.mart.fct_orders`
- `stg_payments` → `iceberg.mart.fct_payments`

Principles:

- Single source (Project 1)
- No data copy
- Query Iceberg directly

### Intermediate (int/)

Business logic; user segmentation:

- `int_user_segments`:
  - High-value: 90d GMV >= 1000
  - Mid-value: 90d GMV >= 500
  - Low-value: else
  - Churn risk: 30d no orders, had orders before
  - Active: 7d has orders
  - Dormant: else

### Mart (mart/)

Final marts for Metrics API and Reverse ETL:

- `mart_kpis_daily_v1`: versioned KPI mart
  - Based on `stg_kpis_daily`
  - Adds payment_success_rate, payment_failure_rate
  - Version v1
- `mart_user_segments`: user-segment mart
  - Based on `int_user_segments`
  - Includes segment_date

## Config

### profiles.yml

```yaml
project_2:
  outputs:
    trino:
      type: trino
      method: none
      host: localhost
      port: 8080
      user: admin
      catalog: iceberg
      schema: mart
  target: trino
```

### dbt_project.yml

```yaml
name: 'project_2'
models:
  project_2:
    stg:
      +materialized: view
    int:
      +materialized: view
    mart:
      +materialized: table
```

## Usage

### Install deps

```bash
cd analytics/dbt
dbt deps
```

### Run models

```bash
dbt run --profiles-dir . --project-dir .
dbt run --select stg_kpis_daily --profiles-dir . --project-dir .
```

### Run tests

```bash
dbt test --profiles-dir . --project-dir .
dbt test --select stg_kpis_daily --profiles-dir . --project-dir .
```

### Docs

```bash
dbt docs generate --profiles-dir . --project-dir .
dbt docs serve --profiles-dir . --project-dir .
```

## Tests

### Schema tests (schema.yml)

- `not_null`, `unique`, `relationships`, `accepted_values`

### Custom

- `test_kpi_completeness`: KPI partition completeness
- `test_payment_amount_consistency`: payment amount consistency

## Versioning

Current: **v1** — `mart_kpis_daily_v1`; API uses `version=v1`.

Future **v2**: add `mart_kpis_daily_v2`, keep v1; API version routing.

## Integration with Project 1

- **Direct ref**: stg models query Project 1 Gold
- **No copy**: single source
- **Alignment**: Project 1 Gold changes flow here

## Troubleshooting

### Trino connection

1. Check `profiles.yml`
2. Confirm Trino is running
3. Test: `trino --server localhost:8080 --catalog iceberg --schema mart`

### Missing tables

1. Run Project 1 first
2. Run Project 1 dbt to build Gold
3. Verify: `SHOW TABLES FROM iceberg.mart`

### Test failures

1. Check data quality
2. `dbt test --store-failures` for details
3. Fix data or tests

## References

- [dbt docs](https://docs.getdbt.com/)
- [Project 2 README](../README.md)
- [Architecture](../docs/architecture.md)
