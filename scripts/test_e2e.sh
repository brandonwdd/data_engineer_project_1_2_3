#!/bin/bash
# End-to-end test script
# Tests Project 1 + Project 2 full integration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_REPORT_DIR="$PROJECT_ROOT/test_reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$TEST_REPORT_DIR"

echo "=========================================="
echo "E2E Test: Project 1 + Project 2"
echo "Timestamp: $TIMESTAMP"
echo "=========================================="
echo ""

# Test results
PASSED=0
FAILED=0
TOTAL=0

test_step() {
    local name=$1
    local command=$2
    
    TOTAL=$((TOTAL + 1))
    echo "[$TOTAL] Test: $name"
    
    if eval "$command" > "$TEST_REPORT_DIR/${TOTAL}_${name// /_}.log" 2>&1; then
        echo "  ✅ Pass"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo "  ❌ Fail"
        FAILED=$((FAILED + 1))
        echo "  Log: $TEST_REPORT_DIR/${TOTAL}_${name// /_}.log"
        return 1
    fi
}

# ============================================
# Project 1 tests
# ============================================

echo "=========================================="
echo "Phase 1: Project 1 tests"
echo "=========================================="
echo ""

# 1.1 Infra check
test_step "Project 1 infra check" "
    cd $PROJECT_ROOT/project_1_cdc_lakehouse_and_dbt_analytics_pipeline/platform/local && \
    docker compose ps | grep -q 'Up' || exit 1
"

# 1.2 Debezium connector
test_step "Debezium connector status" "
    curl -s http://localhost:8083/connectors/project-1-postgres-cdc-docker/status | \
    grep -q '\"state\":\"RUNNING\"' || exit 1
"

# 1.3 Bronze table
test_step "Bronze table data check" "
    trino --server localhost:8080 --execute \
        'SELECT COUNT(*) FROM iceberg.bronze.raw_cdc' | \
    grep -q '[0-9]' || exit 1
"

# 1.4 Silver table
test_step "Silver table data check" "
    trino --server localhost:8080 --execute \
        'SELECT COUNT(*) FROM iceberg.silver.users' | \
    grep -q '[0-9]' || exit 1
"

# 1.5 Gold table
test_step "Gold table data check" "
    trino --server localhost:8080 --execute \
        'SELECT COUNT(*) FROM iceberg.mart.mart_kpis_daily' | \
    grep -q '[0-9]' || exit 1
"

# ============================================
# Project 2 tests
# ============================================

echo ""
echo "=========================================="
echo "Phase 2: Project 2 tests"
echo "=========================================="
echo ""

# 2.1 Project 2 dbt models
test_step "Project 2 dbt models" "
    cd $PROJECT_ROOT/project_2_metrics_api_and_reverse_etl/analytics/dbt && \
    dbt run --profiles-dir . --project-dir . > /dev/null 2>&1
"

# 2.2 Project 2 Gold table
test_step "Project 2 Gold table data check" "
    trino --server localhost:8080 --execute \
        'SELECT COUNT(*) FROM iceberg.mart.mart_kpis_daily_v1' | \
    grep -q '[0-9]' || exit 1
"

# 2.3 Metrics API
test_step "Metrics API health check" "
    curl -s http://localhost:8000/health | \
    grep -q '\"status\":\"healthy\"' || exit 1
"

# 2.4 KPI query
test_step "Metrics API KPI query" "
    curl -s 'http://localhost:8000/kpi?date=$(date +%Y-%m-%d)&version=v1' | \
    grep -q 'total_gmv\|order_count' || exit 1
"

# ============================================
# Integration tests
# ============================================

echo ""
echo "=========================================="
echo "Phase 3: Integration tests"
echo "=========================================="
echo ""

# 3.1 Data consistency
test_step "Project 1 and Project 2 data consistency" "
    P1_COUNT=\$(trino --server localhost:8080 --execute \
        'SELECT COUNT(*) FROM iceberg.mart.mart_kpis_daily' | tail -1)
    P2_COUNT=\$(trino --server localhost:8080 --execute \
        'SELECT COUNT(*) FROM iceberg.mart.mart_kpis_daily_v1' | tail -1)
    [ \"\$P1_COUNT\" = \"\$P2_COUNT\" ] || exit 1
"

# ============================================
# Generate test report
# ============================================

echo ""
echo "=========================================="
echo "Tests complete"
echo "=========================================="
echo ""
echo "Total: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

# Generate report
cat > "$TEST_REPORT_DIR/e2e_test_report_${TIMESTAMP}.md" << EOF
# End-to-End Test Report

**Test time**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Tester**: $(whoami)

## Results

- **Total**: $TOTAL
- **Passed**: $PASSED
- **Failed**: $FAILED
- **Pass rate**: $(echo "scale=2; $PASSED * 100 / $TOTAL" | bc)%

## Logs

All test logs: \`$TEST_REPORT_DIR/\`

## Summary

$(if [ $FAILED -eq 0 ]; then
    echo "✅ All tests passed!"
else
    echo "❌ $FAILED test(s) failed. Check logs."
fi)
EOF

cat "$TEST_REPORT_DIR/e2e_test_report_${TIMESTAMP}.md"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo "✅ All tests passed!"
    exit 0
else
    echo ""
    echo "❌ $FAILED test(s) failed. Check logs."
    exit 1
fi
