# Service Level Objectives (SLO)

## Overview

Project 2 SLOs define service level targets to ensure metrics service reliability and performance.

---

## SLO Definitions

### 1. API Latency

**Metric**: API p95 latency

**Target**: < 300ms

**Measurement**:
- Endpoints: `/kpi`, `/user_segment`
- Point: request start to response
- Aggregation: p95 percentile (5-minute window)

**Monitoring**:
- Datadog APM or Prometheus
- Alert threshold: p95 > 300ms for 5 minutes

**Impact**:
- UX: high latency affects BI/operational tools
- Business: medium (non-critical but affects efficiency)

---

### 2. KPI Freshness

**Metric**: KPI data freshness

**Target**: < 10 minutes

**Definition**: Time from source (Project 1 Gold) update to Metrics API queryable

**Measurement**:
- Query `mart_kpis_daily_v1._computed_at`
- Compute `CURRENT_TIMESTAMP - MAX(_computed_at)`
- Daily partitions should update at least hourly

**Monitoring**:
- Airflow DAG freshness check
- Alert threshold: freshness > 10 minutes

**Impact**:
- Data accuracy: stale data causes decision bias
- Business: high (affects business decisions)

---

### 3. Completeness

**Metric**: Data completeness

**Target**: 100%

**Definition**: All expected partitions must exist

**Measurement**:
- Check last 7 days of daily partitions
- Expected: 7 partitions (one per day)
- Missing partition = completeness failure

**Monitoring**:
- Airflow DAG completeness check
- Alert threshold: any missing partition

**Impact**:
- Data integrity: missing partitions cause inaccurate metrics
- Business: high (affects metric accuracy)

---

### 4. Reverse ETL Success Rate

**Metric**: Reverse ETL task success rate

**Target**: > 99%

**Definition**: Percentage of successful Reverse ETL tasks

**Measurement**:
- Postgres upsert: successful inserts/updates / total records
- Kafka publish: successful messages / total messages
- Task level: Airflow task success rate

**Monitoring**:
- Airflow task metrics
- Alert threshold: success rate < 99% for 1 hour

**Impact**:
- Activation systems: failures cause segment data not synced
- Business: medium (affects operational efficiency)

---

### 5. dbt Tests Pass Rate

**Metric**: dbt tests pass rate

**Target**: 100% (must pass before release)

**Definition**: All dbt tests must pass to release

**Measurement**:
- Airflow DAG `run_dbt_tests` task
- Any test failure = release blocked

**Monitoring**:
- Airflow task status
- Alert: any test failure triggers immediately

**Impact**:
- Data quality: test failure indicates data quality issues
- Business: high (prevents bad data release)

---

## SLO Dashboard

### Key Metrics

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| API p95 latency | < 300ms | - | - |
| KPI freshness | < 10 min | - | - |
| Completeness | 100% | - | - |
| Reverse ETL success rate | > 99% | - | - |
| dbt tests pass rate | 100% | - | - |

### Monitoring Dashboard

**Datadog Dashboard** (TBD):
- API latency trends
- KPI freshness trends
- Completeness status
- Reverse ETL success rate
- dbt tests history

---

## Alert Rules

### 1. API Latency Alert

**Condition**: API p95 latency > 300ms for 5 minutes

**Severity**: Warning

**Notification**: Data Engineering team

**Action**: Check Trino query performance, Iceberg table size, network latency

---

### 2. KPI Freshness Alert

**Condition**: KPI freshness > 10 minutes

**Severity**: Critical

**Notification**: Data Engineering team + On-call

**Action**: Check Project 1 Spark jobs, Airflow DAG status

---

### 3. Completeness Alert

**Condition**: Any expected partition missing

**Severity**: Critical

**Notification**: Data Engineering team + On-call

**Action**: Check Project 1 data pipeline, manually backfill missing partitions

---

### 4. Reverse ETL Failure Alert

**Condition**: Reverse ETL success rate < 99% for 1 hour

**Severity**: Warning

**Notification**: Data Engineering team

**Action**: Check Postgres/Kafka connectivity, network issues, retry mechanism

---

### 5. dbt Tests Failure Alert

**Condition**: Any dbt test failure

**Severity**: Critical

**Notification**: Data Engineering team + On-call

**Action**: Check data quality issues, fix and re-run tests

---

## SLO Review

### Review Cycle

- **Weekly**: Check SLO achievement
- **Monthly**: Review if SLO targets are reasonable
- **Quarterly**: Evaluate if SLO adjustments needed

### Review Content

1. **SLO achievement rate**: Past week/month
2. **Alert frequency**: Alert trigger frequency and causes
3. **Improvements**: Plans for unmet SLOs
4. **Target adjustment**: Whether SLO targets need adjustment

---

## References

- [`runbook/`](../runbook/) — Incident runbooks
- [`docs/architecture.md`](architecture.md) — Architecture
- [`docs/release_process.md`](release_process.md) — Release process
