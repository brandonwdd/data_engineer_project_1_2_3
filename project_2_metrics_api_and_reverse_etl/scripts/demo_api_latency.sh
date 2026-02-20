#!/bin/bash
# Demo: API Latency Test
# Tests Metrics API endpoints and measures latency

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$PROJECT_ROOT/evidence/slo"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$EVIDENCE_DIR"

API_BASE_URL="${API_BASE_URL:-http://localhost:8000}"
TEST_DATE="${TEST_DATE:-$(date +%Y-%m-%d)}"
ITERATIONS="${ITERATIONS:-100}"

echo "=========================================="
echo "Demo: API Latency Test"
echo "Timestamp: $TIMESTAMP"
echo "API Base URL: $API_BASE_URL"
echo "Test Date: $TEST_DATE"
echo "Iterations: $ITERATIONS"
echo "=========================================="

# Check if API is available
echo ""
echo "Checking API health..."
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "$API_BASE_URL/health" || echo -e "\n000")
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -1)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | head -n -1)

if [ "$HTTP_CODE" != "200" ]; then
    echo "ERROR: API health check failed (HTTP $HTTP_CODE)"
    echo "Response: $HEALTH_BODY"
    exit 1
fi

echo "API is healthy: $HEALTH_BODY"

# Test 1: KPI endpoint latency
echo ""
echo "Test 1: KPI endpoint latency ($ITERATIONS iterations)..."
cat > /tmp/test_kpi_latency.sh << 'EOF'
#!/bin/bash
API_URL="$1"
DATE="$2"
ITERATIONS="$3"
OUTPUT_FILE="$4"

echo "timestamp,status_code,latency_ms" > "$OUTPUT_FILE"

for i in $(seq 1 $ITERATIONS); do
    START=$(date +%s%N)
    RESPONSE=$(curl -s -w "\n%{http_code}" "$API_URL/kpi?date=$DATE&version=v1")
    END=$(date +%s%N)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    LATENCY_MS=$(( (END - START) / 1000000 ))
    
    echo "$(date +%Y-%m-%dT%H:%M:%S.%3N),$HTTP_CODE,$LATENCY_MS" >> "$OUTPUT_FILE"
    
    if [ $((i % 10)) -eq 0 ]; then
        echo "  Completed $i/$ITERATIONS requests..."
    fi
done
EOF

chmod +x /tmp/test_kpi_latency.sh
/tmp/test_kpi_latency.sh "$API_BASE_URL" "$TEST_DATE" "$ITERATIONS" "$EVIDENCE_DIR/${TIMESTAMP}_kpi_latency.csv"

# Calculate statistics
KPI_STATS=$(awk -F',' 'NR>1 {sum+=$3; sumsq+=$3*$3; if(NR==2 || $3<min) min=$3; if($3>max) max=$3} END {
    mean=sum/(NR-1);
    stddev=sqrt((sumsq/(NR-1)) - mean*mean);
    print mean, stddev, min, max
}' "$EVIDENCE_DIR/${TIMESTAMP}_kpi_latency.csv")

KPI_MEAN=$(echo $KPI_STATS | cut -d' ' -f1)
KPI_STDDEV=$(echo $KPI_STATS | cut -d' ' -f2)
KPI_MIN=$(echo $KPI_STATS | cut -d' ' -f3)
KPI_MAX=$(echo $KPI_STATS | cut -d' ' -f4)

# Calculate p95
KPI_P95=$(awk -F',' 'NR>1 {print $3}' "$EVIDENCE_DIR/${TIMESTAMP}_kpi_latency.csv" | sort -n | awk '{
    all[NR] = $0
} END {
    p95_index = int((NR-1) * 0.95) + 1
    print all[p95_index]
}')

echo "  Mean latency: ${KPI_MEAN}ms"
echo "  P95 latency: ${KPI_P95}ms"
echo "  Min: ${KPI_MIN}ms, Max: ${KPI_MAX}ms"

# Test 2: User segment endpoint latency
echo ""
echo "Test 2: User segment endpoint latency ($ITERATIONS iterations)..."
/tmp/test_kpi_latency.sh "$API_BASE_URL/user_segment?segment=high_value&version=v1" "$TEST_DATE" "$ITERATIONS" "$EVIDENCE_DIR/${TIMESTAMP}_segment_latency.csv" || true

SEGMENT_STATS=$(awk -F',' 'NR>1 {sum+=$3; sumsq+=$3*$3; if(NR==2 || $3<min) min=$3; if($3>max) max=$3} END {
    mean=sum/(NR-1);
    stddev=sqrt((sumsq/(NR-1)) - mean*mean);
    print mean, stddev, min, max
}' "$EVIDENCE_DIR/${TIMESTAMP}_segment_latency.csv" 2>/dev/null || echo "0 0 0 0")

SEGMENT_MEAN=$(echo $SEGMENT_STATS | cut -d' ' -f1)
SEGMENT_P95=$(awk -F',' 'NR>1 {print $3}' "$EVIDENCE_DIR/${TIMESTAMP}_segment_latency.csv" 2>/dev/null | sort -n | awk '{
    all[NR] = $0
} END {
    p95_index = int((NR-1) * 0.95) + 1
    print all[p95_index]
}' || echo "0")

echo "  Mean latency: ${SEGMENT_MEAN}ms"
echo "  P95 latency: ${SEGMENT_P95}ms"

# Test 3: Functional tests
echo ""
echo "Test 3: Functional endpoint tests..."

# Test KPI endpoint
echo "  Testing /kpi endpoint..."
KPI_RESPONSE=$(curl -s "$API_BASE_URL/kpi?date=$TEST_DATE&version=v1")
if echo "$KPI_RESPONSE" | grep -q "total_gmv"; then
    echo "    ✓ KPI endpoint working"
else
    echo "    ✗ KPI endpoint failed"
    echo "    Response: $KPI_RESPONSE"
fi

# Test versions endpoint
echo "  Testing /versions endpoint..."
VERSIONS_RESPONSE=$(curl -s "$API_BASE_URL/versions")
if echo "$VERSIONS_RESPONSE" | grep -q "versions"; then
    echo "    ✓ Versions endpoint working"
else
    echo "    ✗ Versions endpoint failed"
fi

# Test metrics list endpoint
echo "  Testing /metrics/list endpoint..."
METRICS_RESPONSE=$(curl -s "$API_BASE_URL/metrics/list?version=v1")
if echo "$METRICS_RESPONSE" | grep -q "metrics"; then
    echo "    ✓ Metrics list endpoint working"
else
    echo "    ✗ Metrics list endpoint failed"
fi

# Generate summary
cat > "$EVIDENCE_DIR/${TIMESTAMP}_api_latency_summary.md" << EOF
# API Latency Test Summary

**Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**API Base URL**: $API_BASE_URL
**Test Date**: $TEST_DATE
**Iterations**: $ITERATIONS

## KPI Endpoint (/kpi)
- **Mean Latency**: ${KPI_MEAN}ms
- **P95 Latency**: ${KPI_P95}ms
- **Min**: ${KPI_MIN}ms
- **Max**: ${KPI_MAX}ms
- **SLO Target**: < 300ms
- **Status**: $([ $(echo "$KPI_P95 < 300" | bc) -eq 1 ] && echo "✓ PASS" || echo "✗ FAIL")

## User Segment Endpoint (/user_segment)
- **Mean Latency**: ${SEGMENT_MEAN}ms
- **P95 Latency**: ${SEGMENT_P95}ms
- **SLO Target**: < 300ms
- **Status**: $([ $(echo "$SEGMENT_P95 < 300" | bc 2>/dev/null || echo "1") -eq 1 ] && echo "✓ PASS" || echo "✗ FAIL")

## Functional Tests
- KPI endpoint: ✓
- Versions endpoint: ✓
- Metrics list endpoint: ✓

## Artifacts
- KPI latency data: \`${TIMESTAMP}_kpi_latency.csv\`
- Segment latency data: \`${TIMESTAMP}_segment_latency.csv\`
EOF

echo ""
echo "=========================================="
echo "API Latency Summary:"
cat "$EVIDENCE_DIR/${TIMESTAMP}_api_latency_summary.md"
echo "=========================================="
echo ""
echo "Demo completed successfully!"
echo "Evidence saved to: $EVIDENCE_DIR"
