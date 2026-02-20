# Test Validation Evidence Directory

This directory stores all test validation evidence for Project 1.

## Directory Structure

```
evidence/validation/
├── README.md (this file)
├── acceptance_test_report_YYYY-MM-DD_HHMMSS.md  # Acceptance test report
├── idempotency_test_YYYY-MM-DD_HHMMSS.md        # Idempotency test report
└── test_evidence_package_YYYY-MM-DD_HHMMSS.tar.gz # Test evidence package
```

## How to Generate Test Evidence

### 1. Run Acceptance Tests

```bash
# Method 1: Use script
./scripts/test_acceptance.sh

# Method 2: Use Makefile
make test-acceptance
```

**Output**: `evidence/validation/acceptance_test_report_YYYY-MM-DD_HHMMSS.md`

**Validates**:
- Unit tests pass (16 tests)
- Contract files exist
- Demo scripts exist
- Reconciliation script exists
- K8s config exists
- Docker Compose config exists
- Terraform config exists
- Runbook docs exist
- Quality gate DAG exists
- Documentation completeness

### 2. Run Idempotency Validation

```bash
# Method 1: Use script (default: 3 runs)
./scripts/test_idempotency.sh

# Method 2: Specify number of runs
./scripts/test_idempotency.sh 5

# Method 3: Use Makefile
make test-idempotency
```

**Prerequisites**: 
- MinIO must be running: `cd platform/local && docker compose up -d`
- Postgres must be running: `cd platform/local && docker compose up -d`

**Output**: `evidence/validation/idempotency_test_YYYY-MM-DD_HHMMSS.md`

**Validates**:
- Generate test data window
- Run Bronze ingest + Silver merge (baseline)
- Repeat Silver merge N times
- Verify checksum consistent each time (Silver count, Silver total, Gold KPI)

### 3. Generate Test Evidence Package

```bash
# Method 1: Use script
./scripts/generate_test_evidence.sh

# Method 2: Use Makefile
make test-evidence
```

**Output**: 
- Directory: `evidence/validation/test_evidence_YYYY-MM-DD_HHMMSS/`
- Archive: `evidence/validation/test_evidence_package_YYYY-MM-DD_HHMMSS.tar.gz`

**Contents**:
- Unit test HTML report
- Unit test JUnit XML
- Code coverage report (HTML + XML)
- Acceptance test report
- Idempotency test report (if env available)
- Project structure snapshot
- Demo script validation
- Test summary README

## Test Report Descriptions

### Acceptance Test Report

Includes:
1. **Data correctness**: Unit tests, contract files, table structure
2. **Replay/backfill**: Demo scripts, reconciliation script, checkpoint config
3. **SLA**: Latency, freshness (requires runtime)
4. **Observability**: Datadog config, dashboard, SLO docs
5. **Deployability**: K8s config, Docker Compose, Terraform, storage switch
6. **Governance**: Runbook, quality gates, dbt tests
7. **Documentation completeness**: Architecture, acceptance criteria, SLO, runbook

### Idempotency Test Report

Validates repeated runs of same data window produce consistent results:
- **Baseline (Run 0)**: First run, record checksum
- **Repeated runs (Run 1-N)**: Repeat Silver merge N times
- **Verification**: All runs must have same checksum

**Key metrics**:
- Silver orders count
- Silver test orders total_amount
- Gold total_gmv (if available)
- Gold order_count (if available)

## Acceptance Criteria

See `docs/acceptance_criteria.md`

### Core Requirements

1. ✅ **Data correctness**: No loss, controlled duplicates, eventual consistency, update/delete support, deterministic
2. ✅ **Replay/backfill**: Kafka replay, Bronze recompute, Iceberg time travel
3. ✅ **SLA**: P95 latency < 2 min, Airflow maintenance daily, completeness checks
4. ✅ **Observability**: End-to-end latency, consumer lag, job success rate, freshness, completeness, quality gates
5. ✅ **Deployability**: One-command deploy, config isolation, storage switch
6. ✅ **Governance**: Schema evolution, contracts and quality gates

## Evidence Checklist

Required 8 evidence items:

1. ✅ **Three demo scripts**: `scripts/demo_*.sh`
2. ✅ **Reconciliation reports**: `scripts/run_reconciliation.sh` → `recon/`
3. ✅ **Idempotency acceptance**: `scripts/test_idempotency.sh` → this directory
4. ✅ **Backfill/replay runbook**: `runbook/replay_backfill.md`
5. ✅ **Quality gate evidence**: `orchestration/airflow/dags/quality_gate_cdc.py`
6. ✅ **SLO dashboard**: `observability/dashboards/exports/dashboard.json`
7. ✅ **Release log**: (Project 2, optional)
8. ✅ **Postmortem template**: `docs/postmortem_template.md`

## Run All Tests

```bash
# Run all tests (unit + acceptance)
make test-all

# Or step by step
make test-bronze        # Unit tests
make test-acceptance    # Acceptance tests
make test-idempotency   # Idempotency (requires env)
make test-evidence      # Generate evidence package
```

## Notes

1. **Environment**:
   - Idempotency test requires running Docker (MinIO, Postgres)
   - Most acceptance tests don't need runtime, but some do

2. **Windows users**:
   - Scripts use bash; use Git Bash or WSL
   - Or use Makefile commands (via Docker)

3. **Test duration**:
   - Unit tests: ~1 second
   - Acceptance tests: ~10-30 seconds
   - Idempotency test: ~2-5 minutes (depends on env)

4. **Report locations**:
   - All reports: `evidence/validation/`
   - Reconciliation reports: `recon/`
   - Demo evidence: `evidence/demos/`

---

**Last updated**: 2026-01-16
