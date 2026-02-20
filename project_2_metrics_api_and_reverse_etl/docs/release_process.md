# Metric Release Process

## Overview

The release process ensures all metric changes pass quality gates and are logged.

---

## Release Process

### 1. Code Changes

- Modify dbt models (`analytics/dbt/models/`)
- Commit to Git
- Create Pull Request

### 2. Quality Gate (Airflow DAG)

Airflow DAG `metric_publish_gate` runs:

#### 2.1 Run dbt models

```bash
dbt run --profiles-dir . --project-dir .
```

**On failure**: DAG fails, release blocked

#### 2.2 Run dbt tests

```bash
dbt test --profiles-dir . --project-dir .
```

**Test types**:
- not_null
- unique
- referential integrity
- accepted_values
- Custom sanity checks

**On failure**: DAG fails, release blocked

#### 2.3 Check Completeness

Check expected partitions exist:

```sql
SELECT COUNT(DISTINCT kpi_date) AS partition_count
FROM iceberg.mart.mart_kpis_daily_v1
WHERE kpi_date >= CURRENT_DATE - INTERVAL '7' DAY;
```

**Expected**: 7 partitions (last 7 days)

**On failure**: DAG fails, release blocked

#### 2.4 Insert Release Log

Insert into `metric_release_log`:

```sql
INSERT INTO iceberg.mart.metric_release_log (
    release_id, metric_version, git_commit, git_branch,
    released_by, released_at, dbt_tests_passed,
    completeness_check_passed, data_range_start, data_range_end
) VALUES (...);
```

**Fields**:
- release_id (UUID)
- metric_version (v1, v2, ...)
- git_commit, git_branch
- released_by, released_at
- dbt_tests_passed (boolean)
- completeness_check_passed (boolean)
- data_range_start, data_range_end

#### 2.5 Publish Reverse ETL

Execute Postgres upsert and Kafka publish:

```python
# Postgres upsert
upserter.upsert_segments(segments)

# Kafka publish
publisher.publish_segments(segments)
```

**On failure**:
- Postgres failure → DAG fails
- Kafka failure → log warning (optional: don't block)

---

## Manual Release Process

If Airflow unavailable, run manually:

### 1. Run dbt

```bash
cd analytics/dbt
dbt deps
dbt run
dbt test
```

### 2. Check Completeness

```bash
trino --server localhost:8080 --execute "
SELECT COUNT(DISTINCT kpi_date) 
FROM iceberg.mart.mart_kpis_daily_v1
WHERE kpi_date >= CURRENT_DATE - INTERVAL '7' DAY;
"
```

### 3. Insert Release Log

```sql
INSERT INTO iceberg.mart.metric_release_log (
    release_id, metric_version, git_commit, git_branch,
    released_by, released_at, dbt_tests_passed,
    completeness_check_passed, data_range_start, data_range_end,
    release_notes
) VALUES (
    'manual-2026-01-15-001',
    'v1',
    'abc123...',
    'main',
    'user@example.com',
    CURRENT_TIMESTAMP,
    true,
    true,
    DATE '2026-01-01',
    DATE '2026-01-15',
    'Manual release after dbt tests passed'
);
```

### 4. Execute Reverse ETL

```bash
# Postgres
cd reverse_etl
python postgres/upsert_segments.py

# Kafka
python kafka/publish_segments.py
```

---

## Versioning Strategy

### Current: v1

- Model: `mart_kpis_daily_v1`
- API: `version=v1` parameter

### Future: v2

When metric definitions change:

1. **Create new model**: `mart_kpis_daily_v2`
2. **Keep v1**: Old version remains available
3. **API routing**: API queries table by `version` parameter
4. **Release log**: Record v2 release info

### Version Deprecation

- Keep old version for at least 1 release cycle
- Mark as deprecated in release log
- Notify downstream systems to migrate

---

## Rollback Process

### Scenario 1: dbt Model Error

1. Fix dbt model
2. Re-run `dbt run`
3. Re-run `dbt test`
4. Re-release

### Scenario 2: Data Quality Issue

1. Check Project 1 data pipeline
2. Fix data issue
3. Re-run Project 1 pipeline
4. Re-run Project 2 dbt
5. Re-release

### Scenario 3: Reverse ETL Failure

1. Check Postgres/Kafka connectivity
2. Fix connection
3. Re-run Reverse ETL
4. Verify data sync

---

## Release Checklist

Before release:

- [ ] dbt models ran successfully
- [ ] All dbt tests passed
- [ ] Completeness check passed
- [ ] Release log inserted
- [ ] Reverse ETL executed successfully
- [ ] API endpoints tested
- [ ] Monitoring metrics normal

---

## References

- [`docs/architecture.md`](architecture.md) — Architecture
- [`docs/slo.md`](slo.md) — SLO definitions
- [`runbook/release_process.md`](../runbook/release_process.md) — Runbook
