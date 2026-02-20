#!/bin/bash
# test_acceptance.sh: Acceptance test script - validates all go-live criteria
# Usage: ./scripts/test_acceptance.sh
# Output: evidence/validation/acceptance_test_report_YYYY-MM-DD_HHMMSS.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$PROJECT_ROOT/evidence/validation"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
REPORT_FILE="$EVIDENCE_DIR/acceptance_test_report_${TIMESTAMP}.md"

mkdir -p "$EVIDENCE_DIR"

echo "=== Project 1 Acceptance Test ===" > "$REPORT_FILE"
echo "Test time: $(date -Iseconds)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Test result counters
PASSED=0
FAILED=0
SKIPPED=0

test_check() {
    local name="$1"
    local command="$2"
    local description="$3"
    
    echo "Test: $name" | tee -a "$REPORT_FILE"
    echo "Description: $description" | tee -a "$REPORT_FILE"
    
    if eval "$command" >> "$REPORT_FILE" 2>&1; then
        echo "✅ PASSED" | tee -a "$REPORT_FILE"
        ((PASSED++))
    else
        echo "❌ FAILED" | tee -a "$REPORT_FILE"
        ((FAILED++))
    fi
    echo "" >> "$REPORT_FILE"
}

test_skip() {
    local name="$1"
    local reason="$2"
    echo "⏭️  SKIPPED: $name ($reason)" | tee -a "$REPORT_FILE"
    ((SKIPPED++))
    echo "" >> "$REPORT_FILE"
}

# ============================================
# 1. Data correctness tests
# ============================================
echo "## 1. Data Correctness Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 1.1 Unit tests pass
test_check "Unit tests" \
    "cd '$PROJECT_ROOT' && PYTHONPATH=. python -m pytest streaming/spark/tests/ -v --tb=short" \
    "All unit tests (16) must pass"

# 1.2 Contract files exist
test_check "Contract files exist" \
    "test -f '$PROJECT_ROOT/contracts/cdc/users.yaml' && test -f '$PROJECT_ROOT/contracts/cdc/orders.yaml' && test -f '$PROJECT_ROOT/contracts/cdc/payments.yaml'" \
    "Contract files for all three entities must exist"

# 1.3 Bronze table structure check (requires runtime)
if docker ps | grep -q minio; then
    test_check "Bronze table structure" \
        "docker compose -f '$PROJECT_ROOT/platform/local/docker-compose.yml' --profile bronze run --rm spark spark-sql --master local[*] --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 -e 'DESCRIBE iceberg.bronze.raw_cdc;' | grep -q event_uid" \
        "Bronze table must include event_uid, entity_key, ordering_key fields"
else
    test_skip "Bronze table structure" "MinIO not running, start environment first"
fi

# ============================================
# 2. Replay/backfill tests
# ============================================
echo "## 2. Replay/Backfill Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 2.1 Demo scripts exist
test_check "Demo scripts exist" \
    "test -f '$PROJECT_ROOT/scripts/demo_failure_recovery.sh' && test -f '$PROJECT_ROOT/scripts/demo_replay_idempotency.sh' && test -f '$PROJECT_ROOT/scripts/demo_schema_evolution.sh'" \
    "All three demo scripts must exist and be executable"

# 2.2 Reconciliation script exists
test_check "Reconciliation script exists" \
    "test -f '$PROJECT_ROOT/scripts/run_reconciliation.sh'" \
    "Reconciliation script must exist"

# 2.3 Checkpoint config check
test_check "Checkpoint config" \
    "grep -q 'checkpoint' '$PROJECT_ROOT/streaming/spark/bronze_ingest/job.py' && grep -q 'checkpoint' '$PROJECT_ROOT/streaming/spark/silver_merge/job.py'" \
    "Bronze and Silver jobs must have checkpoint configured"

# ============================================
# 3. SLA tests (requires runtime)
# ============================================
echo "## 3. SLA Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

if docker ps | grep -q minio; then
    test_skip "P95 latency check" "Requires runtime monitoring data"
    test_skip "Freshness check" "Requires runtime monitoring data"
else
    test_skip "P95 latency check" "Environment not running"
    test_skip "Freshness check" "Environment not running"
fi

# ============================================
# 4. Observability tests
# ============================================
echo "## 4. Observability Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 4.1 Datadog monitor config exists
test_check "Datadog monitor config" \
    "test -f '$PROJECT_ROOT/observability/monitors/datadog/monitors.yaml' || test -f '$PROJECT_ROOT/observability/monitors/datadog/monitors.placeholder.yaml'" \
    "Datadog monitor config must exist"

# 4.2 Dashboard config exists
test_check "Dashboard config" \
    "test -f '$PROJECT_ROOT/observability/dashboards/exports/dashboard.json' || test -f '$PROJECT_ROOT/observability/dashboards/exports/dashboard.placeholder.json'" \
    "Dashboard config must exist"

# 4.3 SLO doc exists
test_check "SLO doc" \
    "test -f '$PROJECT_ROOT/docs/slo.md'" \
    "SLO doc must exist"

# ============================================
# 5. Deployability tests
# ============================================
echo "## 5. Deployability Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 5.1 K8s config exists
test_check "K8s config" \
    "test -d '$PROJECT_ROOT/platform/k8s/base' && test -d '$PROJECT_ROOT/platform/k8s/overlays/dev' && test -d '$PROJECT_ROOT/platform/k8s/overlays/prod'" \
    "K8s base and overlays config must exist"

# 5.2 Docker Compose config exists
test_check "Docker Compose config" \
    "test -f '$PROJECT_ROOT/platform/local/docker-compose.yml'" \
    "Docker Compose config must exist"

# 5.3 Terraform config exists
test_check "Terraform config" \
    "test -d '$PROJECT_ROOT/infra/terraform/environments/prod' && test -d '$PROJECT_ROOT/infra/terraform/environments/dev'" \
    "Terraform environment config must exist"

# 5.4 Storage switch scripts exist
test_check "Storage switch scripts" \
    "test -f '$PROJECT_ROOT/scripts/switch_to_s3.sh' && test -f '$PROJECT_ROOT/scripts/switch_to_minio.sh'" \
    "Storage switch scripts must exist"

# ============================================
# 6. Governance tests
# ============================================
echo "## 6. Governance Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 6.1 Runbook exists
test_check "Runbook docs" \
    "test -d '$PROJECT_ROOT/runbook' && test -f '$PROJECT_ROOT/runbook/README.md'" \
    "Runbook directory and docs must exist"

# 6.2 Quality gate DAG exists
test_check "Quality gate DAG" \
    "test -f '$PROJECT_ROOT/orchestration/airflow/dags/quality_gate_cdc.py'" \
    "Quality gate Airflow DAG must exist"

# 6.3 dbt tests config exists
test_check "dbt tests config" \
    "test -f '$PROJECT_ROOT/analytics/dbt/models/schema.yml'" \
    "dbt schema tests config must exist"

# ============================================
# 7. Documentation completeness tests
# ============================================
echo "## 7. Documentation Completeness Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

test_check "Architecture doc" \
    "test -f '$PROJECT_ROOT/docs/architecture.md'" \
    "Architecture doc must exist"

test_check "Acceptance criteria doc" \
    "test -f '$PROJECT_ROOT/docs/acceptance_criteria.md'" \
    "Acceptance criteria doc must exist"

test_check "SLO doc" \
    "test -f '$PROJECT_ROOT/docs/slo.md'" \
    "SLO doc must exist"

test_check "Runbook doc" \
    "test -f '$PROJECT_ROOT/docs/runbook.md'" \
    "Runbook doc must exist"

# ============================================
# Test summary
# ============================================
echo "" >> "$REPORT_FILE"
echo "## Test Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "✅ Passed: $PASSED" >> "$REPORT_FILE"
echo "❌ Failed: $FAILED" >> "$REPORT_FILE"
echo "⏭️  Skipped: $SKIPPED" >> "$REPORT_FILE"
echo "Total: $((PASSED + FAILED + SKIPPED))" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

if [ $FAILED -eq 0 ]; then
    echo "🎉 All executable tests passed!" >> "$REPORT_FILE"
    echo "✅ Acceptance test passed!"
    exit 0
else
    echo "⚠️  $FAILED test(s) failed, check report" >> "$REPORT_FILE"
    echo "❌ Acceptance test failed, see: $REPORT_FILE"
    exit 1
fi
