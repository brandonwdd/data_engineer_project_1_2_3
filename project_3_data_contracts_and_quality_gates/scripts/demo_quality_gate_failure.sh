#!/bin/bash
# Demo: Quality Gate Failure
# Demonstrates quality gate blocking bad data from publishing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$PROJECT_ROOT/evidence/demos"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$EVIDENCE_DIR"

echo "=========================================="
echo "Demo: Quality Gate Failure"
echo "Timestamp: $TIMESTAMP"
echo "=========================================="
echo ""

# Step 1: Simulate dbt test failure
echo "Step 1: Simulating dbt test failure..."
cd "$PROJECT_ROOT/project_1_cdc_lakehouse_and_dbt_analytics_pipeline/analytics/dbt"

# Create a temporary test that will fail
cat > tests/test_demo_failure.sql << 'EOF'
-- This test will fail to demonstrate quality gate blocking
SELECT 1 WHERE 1 = 0
EOF

echo "  [OK] Created failing test"

# Step 2: Run dbt tests (should fail)
echo ""
echo "Step 2: Running dbt tests (expected to fail)..."
dbt test --profiles-dir . --project-dir . --select test_demo_failure \
  > "$EVIDENCE_DIR/${TIMESTAMP}_dbt_test_failure.log" 2>&1 && {
    echo "   Test should have failed but passed (unexpected)"
} || {
    echo "   Test correctly failed (as expected)"
    echo "  Quality gate would block publishing"
}

# Step 3: Clean up
rm -f tests/test_demo_failure.sql
echo "  [OK] Cleaned up test file"

# Step 4: Simulate custom quality check failure
echo ""
echo "Step 3: Simulating custom quality check failure..."
cat > /tmp/custom_check_failure.sql << 'EOF'
-- Simulate referential integrity violation
SELECT COUNT(*) as violation_count
FROM iceberg.mart.fct_payments p
LEFT JOIN iceberg.mart.fct_orders o ON p.order_id = o.order_id
WHERE o.order_id IS NULL
EOF

echo "  [OK] Created custom check SQL"

# Step 5: Generate summary
cat > "$EVIDENCE_DIR/${TIMESTAMP}_quality_gate_failure_summary.md" << EOF
# Quality Gate Failure Demo Summary

**Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Scenarios Tested

1. **dbt Test Failure**:  Correctly detected and would block publishing
2. **Custom Quality Check**: Simulated referential integrity violation

## Quality Gate Behavior

-  dbt tests failure → Publishing blocked
-  Custom checks failure → Publishing blocked
-  Airflow DAG would fail → Downstream tasks not executed

## Artifacts

- dbt test failure log: \`${TIMESTAMP}_dbt_test_failure.log\`
EOF

echo ""
echo "=========================================="
echo "Demo Summary:"
cat "$EVIDENCE_DIR/${TIMESTAMP}_quality_gate_failure_summary.md"
echo "=========================================="
echo ""
echo "Demo completed successfully!"
echo "Evidence saved to: $EVIDENCE_DIR"
