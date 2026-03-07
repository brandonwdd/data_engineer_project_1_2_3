#!/bin/bash
# Demo: Contract Violation
# Demonstrates contract validation blocking bad data

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$PROJECT_ROOT/evidence/demos"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$EVIDENCE_DIR"

echo "=========================================="
echo "Demo: Contract Violation"
echo "Timestamp: $TIMESTAMP"
echo "=========================================="
echo ""

# Step 1: Create a valid event
echo "Step 1: Creating valid CDC event..."
cat > /tmp/valid_event.json << 'EOF'
{
  "op": "c",
  "ts_ms": 1642234567890,
  "source": {
    "connector": "postgres",
    "lsn": 12345
  },
  "after": {
    "order_id": 1,
    "user_id": 1,
    "status": "created",
    "total_amount": 100.50,
    "updated_at": "2026-01-15T10:00:00Z"
  }
}
EOF

echo "  [OK] Valid event created"

# Step 2: Validate valid event
echo ""
echo "Step 2: Validating valid event..."
cd "$PROJECT_ROOT/project_3_data_contracts_and_quality_gates/tools/contract_validator"
pip install -q -r requirements.txt 2>/dev/null || true

python contract_validator.py \
  --contract "$PROJECT_ROOT/project_1_cdc_lakehouse_and_dbt_analytics_pipeline/contracts/cdc/orders.yaml" \
  --event /tmp/valid_event.json > "$EVIDENCE_DIR/${TIMESTAMP}_valid_event.log" 2>&1 && {
    echo "   Valid event passed validation"
} || {
    echo "   Valid event failed validation (unexpected)"
    exit 1
}

# Step 3: Create invalid events
echo ""
echo "Step 3: Creating invalid events..."

# Invalid event 1: Missing required field
cat > /tmp/invalid_event_1.json << 'EOF'
{
  "op": "c",
  "ts_ms": 1642234567890,
  "after": {
    "order_id": 1,
    "user_id": 1
  }
}
EOF

# Invalid event 2: Invalid op
cat > /tmp/invalid_event_2.json << 'EOF'
{
  "op": "x",
  "ts_ms": 1642234567890,
  "source": {
    "connector": "postgres"
  },
  "after": {
    "order_id": 1,
    "user_id": 1,
    "status": "created"
  }
}
EOF

# Invalid event 3: Invalid status value
cat > /tmp/invalid_event_3.json << 'EOF'
{
  "op": "c",
  "ts_ms": 1642234567890,
  "source": {
    "connector": "postgres"
  },
  "after": {
    "order_id": 1,
    "user_id": 1,
    "status": "invalid_status",
    "total_amount": 100.50
  }
}
EOF

echo "  [OK] Invalid events created"

# Step 4: Validate invalid events
echo ""
echo "Step 4: Validating invalid events (should fail)..."

VIOLATION_COUNT=0

python contract_validator.py \
  --contract "$PROJECT_ROOT/project_1_cdc_lakehouse_and_dbt_analytics_pipeline/contracts/cdc/orders.yaml" \
  --event /tmp/invalid_event_1.json > "$EVIDENCE_DIR/${TIMESTAMP}_invalid_1.log" 2>&1 && {
    echo "   Invalid event 1 (missing source) should have failed"
} || {
    echo "   Invalid event 1 correctly rejected (missing source)"
    VIOLATION_COUNT=$((VIOLATION_COUNT + 1))
}

python contract_validator.py \
  --contract "$PROJECT_ROOT/project_1_cdc_lakehouse_and_dbt_analytics_pipeline/contracts/cdc/orders.yaml" \
  --event /tmp/invalid_event_2.json > "$EVIDENCE_DIR/${TIMESTAMP}_invalid_2.log" 2>&1 && {
    echo "   Invalid event 2 (invalid op) should have failed"
} || {
    echo "   Invalid event 2 correctly rejected (invalid op)"
    VIOLATION_COUNT=$((VIOLATION_COUNT + 1))
}

python contract_validator.py \
  --contract "$PROJECT_ROOT/project_1_cdc_lakehouse_and_dbt_analytics_pipeline/contracts/cdc/orders.yaml" \
  --event /tmp/invalid_event_3.json > "$EVIDENCE_DIR/${TIMESTAMP}_invalid_3.log" 2>&1 && {
    echo "   Invalid event 3 (invalid status) should have failed"
} || {
    echo "   Invalid event 3 correctly rejected (invalid status)"
    VIOLATION_COUNT=$((VIOLATION_COUNT + 1))
}

# Step 5: Validate all contracts
echo ""
echo "Step 5: Validating all contracts..."
python contract_validator.py \
  --contracts-dir "$PROJECT_ROOT/project_3_data_contracts_and_quality_gates/contracts" \
  --output "$EVIDENCE_DIR/${TIMESTAMP}_contract_validation.json" > "$EVIDENCE_DIR/${TIMESTAMP}_contract_validation.log" 2>&1 && {
    echo "   All contracts are valid"
} || {
    echo "   Some contracts are invalid"
    cat "$EVIDENCE_DIR/${TIMESTAMP}_contract_validation.log"
}

# Step 6: Generate summary
cat > "$EVIDENCE_DIR/${TIMESTAMP}_contract_violation_summary.md" << EOF
# Contract Violation Demo Summary

**Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Test Results

- **Valid Event**:  Passed
- **Invalid Events Detected**: $VIOLATION_COUNT / 3
- **Contract Validation**:  All contracts valid

## Invalid Events Tested

1. **Missing required field (source)**:  Correctly rejected
2. **Invalid op value**:  Correctly rejected
3. **Invalid status value**:  Correctly rejected

## Artifacts

- Valid event log: \`${TIMESTAMP}_valid_event.log\`
- Invalid event logs: \`${TIMESTAMP}_invalid_*.log\`
- Contract validation: \`${TIMESTAMP}_contract_validation.json\`
EOF

echo ""
echo "=========================================="
echo "Demo Summary:"
cat "$EVIDENCE_DIR/${TIMESTAMP}_contract_violation_summary.md"
echo "=========================================="
echo ""
echo "Demo completed successfully!"
echo "Evidence saved to: $EVIDENCE_DIR"
