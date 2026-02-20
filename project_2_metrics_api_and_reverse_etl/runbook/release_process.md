# Release Process Runbook

## Overview

This runbook provides operational guidance for the metric release process.

---

## Normal Release Process

### Automatic Release (Recommended)

Airflow DAG `metric_publish_gate` runs daily at 2:00 AM.

**Check DAG status**:
```bash
# View DAG runs
airflow dags list-runs -d metric_publish_gate

# View latest run logs
airflow tasks logs metric_publish_gate run_dbt_tests <run_id>
```

### Manual Trigger

If manual trigger needed:

```bash
# Trigger DAG
airflow dags trigger metric_publish_gate

# Or use Airflow UI
# http://airflow-host:8080/admin/airflow/graph?dag_id=metric_publish_gate
```

---

## Incident Handling

### Incident 1: dbt Tests Failure

**Symptom**: `run_dbt_tests` task fails

**Diagnosis**:
```bash
# View failure details
airflow tasks logs metric_publish_gate run_dbt_tests <run_id>

# Reproduce locally
cd analytics/dbt
dbt test --profiles-dir . --project-dir .
```

**Steps**:
1. Check failed test name
2. Inspect corresponding data table
3. Fix data issue or adjust test logic
4. Re-run dbt test
5. Re-trigger DAG

**Common causes**:
- Data quality (nulls, duplicates)
- Referential integrity violations
- Enum value mismatches

---

### Incident 2: Completeness Check Failure

**Symptom**: `check_completeness` task fails

**Diagnosis**:
```bash
# View failure details
airflow tasks logs metric_publish_gate check_completeness <run_id>

# Manual partition check
trino --server localhost:8080 --execute "
SELECT 
    kpi_date,
    COUNT(*) AS row_count
FROM iceberg.mart.mart_kpis_daily_v1
WHERE kpi_date >= CURRENT_DATE - INTERVAL '7' DAY
GROUP BY kpi_date
ORDER BY kpi_date;
"
```

**Steps**:
1. Identify missing partition dates
2. Check Project 1 data pipeline status
3. If Project 1 OK, check dbt model logic
4. Manually backfill missing partitions (if needed)
5. Re-trigger DAG

**Common causes**:
- Project 1 Spark job failures
- Data source issues
- Timezone issues

---

### Incident 3: Reverse ETL Failure

**Symptom**: `publish_reverse_etl` task fails

**Diagnosis**:
```bash
# View failure details
airflow tasks logs metric_publish_gate publish_reverse_etl <run_id>
```

**Postgres failure**:
```bash
# Check Postgres connection
psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;"

# Check table exists
psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "\d customer_segments"
```

**Kafka failure**:
```bash
# Check Kafka connection
kafka-topics.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --list

# Check topic exists
kafka-topics.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --describe --topic segment_updates
```

**Steps**:
1. Check connection config
2. Fix connection
3. Manually run Reverse ETL scripts
4. Verify data sync
5. Re-trigger DAG

---

### Incident 4: Release Log Insert Failure

**Symptom**: `insert_release_log` task fails

**Diagnosis**:
```bash
# Check table exists
trino --server localhost:8080 --execute "
SHOW TABLES FROM iceberg.mart LIKE 'metric_release_log';
"

# Check table structure
trino --server localhost:8080 --execute "
DESCRIBE iceberg.mart.metric_release_log;
"
```

**Steps**:
1. Confirm table created (run DDL)
2. Check Trino connection
3. Manually insert release log (if needed)
4. Re-trigger DAG

---

## Rollback Operations

### Rollback dbt Models

If newly released model has issues:

```bash
# 1. Revert Git commit
git revert <commit_hash>

# 2. Re-run dbt
cd analytics/dbt
dbt run --profiles-dir . --project-dir .

# 3. Verify data
trino --server localhost:8080 --execute "
SELECT * FROM iceberg.mart.mart_kpis_daily_v1 
WHERE kpi_date = CURRENT_DATE 
LIMIT 10;
"
```

### Rollback Reverse ETL

If Postgres data needs rollback:

```sql
-- Delete data by run_id
DELETE FROM customer_segments
WHERE source_run_id = '<run_id>';

-- Or restore from previous snapshot (if backup exists)
```

---

## Monitoring and Alerts

### Key Metrics

- **DAG success rate**: Should be > 99%
- **dbt tests pass rate**: Should be = 100%
- **Completeness**: Should be = 100%
- **Reverse ETL success rate**: Should be > 99%

### Alert Rules

- DAG fails 3 times consecutively → alert
- dbt tests fail → immediate alert
- Completeness fails → immediate alert
- Reverse ETL fails → alert

### View Release History

```sql
SELECT 
    release_id,
    metric_version,
    released_at,
    dbt_tests_passed,
    completeness_check_passed,
    data_range_start,
    data_range_end
FROM iceberg.mart.metric_release_log
ORDER BY released_at DESC
LIMIT 10;
```

---

## Best Practices

1. **Test before release**: Test in dev first
2. **Small releases**: Avoid large changes at once
3. **Monitor release**: Check metrics immediately after
4. **Document issues**: Record all issues in postmortem
5. **Regular review**: Review release process weekly

---

## References

- [`docs/release_process.md`](../docs/release_process.md) — Release process doc
- [`docs/slo.md`](../docs/slo.md) — SLO definitions
- [`../evidence/postmortems/`](../evidence/postmortems/) — Postmortems
