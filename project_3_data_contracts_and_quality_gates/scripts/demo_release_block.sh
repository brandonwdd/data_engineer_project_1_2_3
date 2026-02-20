#!/bin/bash
# Demo: Release Block
# Demonstrates how quality gates block releases

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$PROJECT_ROOT/evidence/demos"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$EVIDENCE_DIR"

echo "=========================================="
echo "Demo: Release Block"
echo "Timestamp: $TIMESTAMP"
echo "=========================================="
echo ""

# Step 1: Validate contracts
echo "Step 1: Validating contracts..."
cd "$PROJECT_ROOT/project_3_data_contracts_and_quality_gates/tools/contract_validator"
pip install -q -r requirements.txt 2>/dev/null || true

python contract_validator.py \
  --contracts-dir "$PROJECT_ROOT/project_3_data_contracts_and_quality_gates/contracts" \
  > "$EVIDENCE_DIR/${TIMESTAMP}_contract_validation.log" 2>&1 && {
    echo "  ✅ Contracts valid"
    CONTRACT_STATUS="passed"
} || {
    echo "  ❌ Contracts invalid - RELEASE BLOCKED"
    CONTRACT_STATUS="failed"
    cat "$EVIDENCE_DIR/${TIMESTAMP}_contract_validation.log"
}

# Step 2: Run dbt tests (Project 1)
echo ""
echo "Step 2: Running Project 1 dbt tests..."
cd "$PROJECT_ROOT/project_1_cdc_lakehouse_and_dbt_analytics_pipeline/analytics/dbt"
dbt test --profiles-dir . --project-dir . \
  > "$EVIDENCE_DIR/${TIMESTAMP}_dbt_project1.log" 2>&1 && {
    echo "  ✅ Project 1 dbt tests passed"
    DBT1_STATUS="passed"
} || {
    echo "  ❌ Project 1 dbt tests failed - RELEASE BLOCKED"
    DBT1_STATUS="failed"
}

# Step 3: Run dbt tests (Project 2)
echo ""
echo "Step 3: Running Project 2 dbt tests..."
cd "$PROJECT_ROOT/project_2_metrics_api_and_reverse_etl/analytics/dbt"
dbt test --profiles-dir . --project-dir . \
  > "$EVIDENCE_DIR/${TIMESTAMP}_dbt_project2.log" 2>&1 && {
    echo "  ✅ Project 2 dbt tests passed"
    DBT2_STATUS="passed"
} || {
    echo "  ❌ Project 2 dbt tests failed - RELEASE BLOCKED"
    DBT2_STATUS="failed"
}

# Step 4: Check completeness
echo ""
echo "Step 4: Checking completeness..."
# Placeholder - would check partition completeness
echo "  ✓ Completeness check (placeholder)"

# Step 5: Final decision
echo ""
echo "=========================================="
echo "Release Gate Decision:"
echo "=========================================="

ALL_PASSED=true

if [ "$CONTRACT_STATUS" != "passed" ]; then
    echo "  ❌ Contract validation: FAILED"
    ALL_PASSED=false
else
    echo "  ✅ Contract validation: PASSED"
fi

if [ "$DBT1_STATUS" != "passed" ]; then
    echo "  ❌ Project 1 dbt tests: FAILED"
    ALL_PASSED=false
else
    echo "  ✅ Project 1 dbt tests: PASSED"
fi

if [ "$DBT2_STATUS" != "passed" ]; then
    echo "  ❌ Project 2 dbt tests: FAILED"
    ALL_PASSED=false
else
    echo "  ✅ Project 2 dbt tests: PASSED"
fi

echo ""
if [ "$ALL_PASSED" = true ]; then
    echo "✅ ALL GATES PASSED - Release allowed"
    RELEASE_DECISION="allow"
else
    echo "❌ GATES FAILED - Release BLOCKED"
    RELEASE_DECISION="block"
fi

# Step 6: Generate summary
cat > "$EVIDENCE_DIR/${TIMESTAMP}_release_block_summary.md" << EOF
# Release Block Demo Summary

**Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Quality Gate Results

| Gate | Status |
|------|--------|
| Contract Validation | $CONTRACT_STATUS |
| Project 1 dbt Tests | $DBT1_STATUS |
| Project 2 dbt Tests | $DBT2_STATUS |
| Completeness Check | passed (placeholder) |

## Release Decision

**Decision**: $RELEASE_DECISION

$(if [ "$ALL_PASSED" = true ]; then
    echo "✅ All quality gates passed - publishing allowed"
else
    echo "❌ Quality gates failed - publishing blocked"
fi)

## Artifacts

- Contract validation: \`${TIMESTAMP}_contract_validation.log\`
- Project 1 dbt tests: \`${TIMESTAMP}_dbt_project1.log\`
- Project 2 dbt tests: \`${TIMESTAMP}_dbt_project2.log\`
EOF

echo ""
echo "=========================================="
cat "$EVIDENCE_DIR/${TIMESTAMP}_release_block_summary.md"
echo "=========================================="
echo ""
echo "Demo completed!"
echo "Evidence saved to: $EVIDENCE_DIR"
