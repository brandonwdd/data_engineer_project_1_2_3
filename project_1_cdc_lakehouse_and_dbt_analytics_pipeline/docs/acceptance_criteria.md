# Acceptance Criteria

This document defines the go-live criteria for Project 1: Real-time CDC Lakehouse.

## 1. Data Correctness

### 1.1 No Data Loss
- ✅ **Verification**: Demo-1 failure recovery script + reconciliation report
- ✅ **Criteria**:
  - Bronze `event_uid` continuity check (no gap)
  - Silver PK row-count reconciliation (matches source)
  - Gold KPI checksum reconciliation (matches expected)

### 1.2 Controlled Duplicates (Idempotency)
- ✅ **Verification**: Demo-2 replay idempotency script + idempotency test (`test_idempotency.sh`)
- ✅ **Criteria**:
  - Same window re-run N=3 times; Gold KPI checksum unchanged
  - Silver PK uniqueness (one row per `entity_key`)
  - `ordering_key` comparison correct (keeps latest)

### 1.3 Eventually Consistent
- ✅ **Verification**: Reconciliation script (`run_reconciliation.sh`)
- ✅ **Criteria**:
  - Bronze/Silver/Gold layer consistency
  - Completeness checks on key tables

### 1.4 Update/Delete Support
- ✅ **Verification**: Unit tests + demo scripts
- ✅ **Criteria**:
  - Debezium `op='d'` correctly parsed as DELETE
  - Silver MERGE INTO correctly handles DELETE
  - Post-delete reconciliation (row count decrease)

### 1.5 Deterministic Results
- ✅ **Verification**: Idempotency tests
- ✅ **Criteria**:
  - `ordering_key` well-defined (lsn first, clear fallback)
  - Same input → same output (stable checksum)

## 2. Replay / Backfill

### 2.1 Kafka Replay
- ✅ **Verification**: Demo-2 script
- ✅ **Criteria**:
  - Support reset consumer group offsets
  - Support new consumer group re-run
  - Replay results match first run

### 2.2 Bronze Recompute
- ✅ **Verification**: Reconciliation script + backfill DAG
- ✅ **Criteria**:
  - Silver/Gold can be recomputed from Bronze `raw_cdc`
  - Recompute results match first run (idempotent)

### 2.3 Iceberg Time Travel
- ✅ **Verification**: Demo-3 script + docs
- ✅ **Criteria**:
  - Support query by snapshot_id / timestamp
  - Support rollback / branch / tag (bonus)

## 3. SLA

### 3.1 Latency
- **Target**: P95 end-to-end data latency < 2 minutes (configurable)
- **Verification**: Datadog dashboard + metrics
- **Criteria**:
  - Monitoring configured
  - Latency metrics available (ingestion + serving)

### 3.2 Airflow Maintenance
- **Target**: Daily completion
- **Verification**: Airflow DAG run history
- **Criteria**:
  - `maintenance_iceberg.py` DAG runs daily
  - Compact, expire snapshots, remove orphans complete

### 3.3 Completeness
- **Target**: Key tables have completeness checks
- **Verification**: dbt tests + reconciliation
- **Criteria**:
  - Daily partition completeness (expected partitions present)
  - Missing partitions trigger alert

## 4. Observability

### 4.1 End-to-End Latency
- ✅ **Verification**: Datadog dashboard
- ✅ **Criteria**:
  - Dashboard configured
  - Latency metrics available

### 4.2 Consumer Lag
- ✅ **Verification**: Datadog monitors
- ✅ **Criteria**:
  - Monitor rules configured
  - Lag > threshold triggers alert

### 4.3 Job Success Rate
- ✅ **Verification**: Datadog monitors
- ✅ **Criteria**:
  - Spark job success/failure monitored
  - Airflow DAG success rate monitored

### 4.4 Data Freshness
- ✅ **Verification**: Datadog monitors
- ✅ **Criteria**:
  - Last successful write time per key table
  - Freshness breach triggers alert

### 4.5 Output Completeness
- ✅ **Verification**: dbt tests + Datadog
- ✅ **Criteria**:
  - Day/hour partition completeness checks
  - Missing partitions trigger alert

### 4.6 Data Quality Gate Pass Rate
- ✅ **Verification**: Airflow quality gate DAG
- ✅ **Criteria**:
  - dbt tests pass rate monitored
  - Failure blocks release

## 5. Deployability

### 5.1 One-Command Deploy
- ✅ **Verification**: Makefile + K8s config
- ✅ **Criteria**:
  - `make deploy-k8s-dev/stg/prod` works
  - Kustomize overlays configured

### 5.2 Config Isolation
- ✅ **Verification**: K8s overlays + Terraform
- ✅ **Criteria**:
  - dev/stg/prod config isolated
  - ConfigMap + Secret used correctly

### 5.3 Storage Switch
- ✅ **Verification**: Switch scripts
- ✅ **Criteria**:
  - `switch_to_s3.sh` / `switch_to_minio.sh` executable
  - Terraform output correctly mapped to Spark config

## 6. Governance

### 6.1 Schema Evolution
- ✅ **Verification**: Demo-3 script
- ✅ **Criteria**:
  - Add: backward-compatible (nullable or default)
  - Delete: deprecate cycle (≥ 1–2 versions)
  - End-to-end compatibility verified

### 6.2 Contracts and Quality Gates
- ✅ **Verification**: Contract files + quality gate DAG
- ✅ **Criteria**:
  - Contract files exist (`contracts/cdc/*.yaml`)
  - Quality gate failure blocks release
  - Alerting configured

## 7. Evidence Requirements

### 7.1 Three Demo Scripts (must run with one command)
- ✅ `demo_failure_recovery.sh`: kill job → recover → reconciliation pass
- ✅ `demo_replay_idempotency.sh`: reset offsets → re-run → checksum unchanged
- ✅ `demo_schema_evolution.sh`: add field → end-to-end compatible

### 7.2 Reconciliation Reports (must be produced)
- ✅ `run_reconciliation.sh`: produces Bronze/Silver/Gold reconciliation report
- ✅ Output to `recon/` with timestamp

### 7.3 Idempotency Acceptance (must be quantified)
- ✅ `test_idempotency.sh`: re-run N=3 times, checksum unchanged
- ✅ Report output to `evidence/validation/`

### 7.4 Quality Gate Evidence
- ✅ Airflow blocks downstream when dbt tests fail
- ✅ Alert logs/metrics recorded

### 7.5 SLO Dashboard
- ✅ Datadog dashboard configured
- ✅ At least: consumer lag, end-to-end latency, completeness, dbt tests pass rate

### 7.6 Test Reports
- ✅ Unit test report (HTML + coverage)
- ✅ Acceptance test report (`test_acceptance.sh`)
- ✅ Idempotency test report (`test_idempotency.sh`)

## 8. Acceptance Test Scripts

Run acceptance tests:

```bash
# Run all acceptance tests
./scripts/test_acceptance.sh

# Run idempotency verification (requires running env)
./scripts/test_idempotency.sh [N=3]

# Generate test evidence bundle
./scripts/generate_test_evidence.sh
```

## 9. Acceptance Pass Criteria

- ✅ All unit tests pass (16 tests)
- ✅ Acceptance tests pass (`test_acceptance.sh`)
- ✅ Idempotency verified (re-run N times, checksum unchanged)
- ✅ Three demo scripts runnable
- ✅ Reconciliation report generated
- ✅ Docs complete (README, SLO, Runbook, architecture)

---

**Last updated**: $(date +%Y-%m-%d)
