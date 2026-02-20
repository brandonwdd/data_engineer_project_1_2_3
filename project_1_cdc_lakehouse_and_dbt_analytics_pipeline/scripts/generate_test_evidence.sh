#!/bin/bash
# generate_test_evidence.sh: Generate test evidence package
# Usage: ./scripts/generate_test_evidence.sh
# Output: evidence/validation/test_evidence_package_YYYY-MM-DD_HHMMSS.tar.gz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$PROJECT_ROOT/evidence/validation"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
PACKAGE_DIR="$EVIDENCE_DIR/test_evidence_${TIMESTAMP}"
PACKAGE_FILE="$EVIDENCE_DIR/test_evidence_package_${TIMESTAMP}.tar.gz"

mkdir -p "$PACKAGE_DIR"

echo "=== Generate Test Evidence Package ==="
echo "Output directory: $PACKAGE_DIR"

# 1. Run unit tests and save report
echo "1. Running unit tests..."
PYTHONPATH=. python -m pytest streaming/spark/tests/ -v --tb=short \
    --html="$PACKAGE_DIR/unit_test_report.html" \
    --self-contained-html \
    --junit-xml="$PACKAGE_DIR/unit_test_results.xml" \
    --cov=streaming/spark \
    --cov-report=html:"$PACKAGE_DIR/coverage_html" \
    --cov-report=xml:"$PACKAGE_DIR/coverage.xml" \
    > "$PACKAGE_DIR/unit_test_output.txt" 2>&1 || true

# 2. Run acceptance tests
echo "2. Running acceptance tests..."
"$SCRIPT_DIR/test_acceptance.sh" || true
cp "$EVIDENCE_DIR"/acceptance_test_report_*.md "$PACKAGE_DIR/" 2>/dev/null || true

# 3. Run idempotency test (if env available)
if docker ps | grep -q minio; then
    echo "3. Running idempotency test..."
    "$SCRIPT_DIR/test_idempotency.sh" 3 || true
    cp "$EVIDENCE_DIR"/idempotency_test_*.md "$PACKAGE_DIR/" 2>/dev/null || true
else
    echo "3. Skipping idempotency test (environment not running)"
fi

# 4. Collect code coverage
echo "4. Collecting code coverage..."
if [ -f "$PACKAGE_DIR/coverage.xml" ]; then
    python3 <<'PYTHON_EOF'
import xml.etree.ElementTree as ET
import sys

try:
    tree = ET.parse(sys.argv[1])
    root = tree.getroot()
    
    # Extract coverage
    coverage = root.get('line-rate', '0')
    print(f"Code coverage: {float(coverage) * 100:.2f}%")
except:
    print("Cannot parse coverage report")
PYTHON_EOF
"$PACKAGE_DIR/coverage.xml" > "$PACKAGE_DIR/coverage_summary.txt" || true
fi

# 5. Collect project structure snapshot
echo "5. Collecting project structure..."
{
    echo "# Project Structure Snapshot"
    echo "Generated: $(date -Iseconds)"
    echo ""
    echo "## Key Files"
    find . -type f -name "*.py" -o -name "*.sql" -o -name "*.yaml" -o -name "*.yml" | \
        grep -E "(streaming|contracts|analytics|orchestration)" | \
        sort > "$PACKAGE_DIR/project_structure.txt"
    
    echo ""
    echo "## Test Files"
    find streaming/spark/tests -type f | sort >> "$PACKAGE_DIR/project_structure.txt"
} > "$PACKAGE_DIR/project_structure.txt"

# 6. Collect demo script validation
echo "6. Validating demo scripts..."
{
    echo "# Demo Script Validation"
    echo "Generated: $(date -Iseconds)"
    echo ""
    for script in demo_failure_recovery.sh demo_replay_idempotency.sh demo_schema_evolution.sh; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            if [ -x "$SCRIPT_DIR/$script" ]; then
                echo "✅ $script: exists and executable"
            else
                echo "⚠️  $script: exists but not executable"
            fi
        else
            echo "❌ $script: not found"
        fi
    done
} > "$PACKAGE_DIR/demo_scripts_validation.txt"

# 7. Generate test summary report
echo "7. Generating test summary report..."
cat > "$PACKAGE_DIR/README.md" <<EOF
# Test Evidence Package

Generated: $(date -Iseconds)

## Contents

1. **Unit Test Report**
   - HTML: \`unit_test_report.html\`
   - JUnit XML: \`unit_test_results.xml\`
   - Coverage: \`coverage_html/index.html\`

2. **Acceptance Test Report**
   - Acceptance: \`acceptance_test_report_*.md\`

3. **Idempotency Test Report** (if env available)
   - Idempotency: \`idempotency_test_*.md\`

4. **Project Structure Snapshot**
   - File list: \`project_structure.txt\`

5. **Demo Script Validation**
   - Results: \`demo_scripts_validation.txt\`

## How to View

- Unit test HTML: open \`unit_test_report.html\`
- Coverage: open \`coverage_html/index.html\`
- Acceptance: see \`acceptance_test_report_*.md\`
- Idempotency: see \`idempotency_test_*.md\`

## Test Status

$(if [ -f "$PACKAGE_DIR/unit_test_output.txt" ]; then
    echo "Unit tests:"
    tail -5 "$PACKAGE_DIR/unit_test_output.txt" | sed 's/^/  /'
fi)

EOF

# 8. Package
echo "8. Packaging evidence..."
cd "$EVIDENCE_DIR"
tar -czf "$(basename "$PACKAGE_FILE")" "test_evidence_${TIMESTAMP}/" 2>/dev/null || \
    zip -r "$(basename "$PACKAGE_FILE" .tar.gz).zip" "test_evidence_${TIMESTAMP}/" > /dev/null 2>&1

echo ""
echo "✅ Test evidence package generated:"
echo "   Directory: $PACKAGE_DIR"
if [ -f "$PACKAGE_FILE" ]; then
    echo "   Archive: $PACKAGE_FILE"
elif [ -f "${PACKAGE_FILE%.tar.gz}.zip" ]; then
    echo "   Archive: ${PACKAGE_FILE%.tar.gz}.zip"
fi
echo ""
echo "View reports:"
echo "  - Unit tests: $PACKAGE_DIR/unit_test_report.html"
echo "  - Coverage: $PACKAGE_DIR/coverage_html/index.html"
echo "  - Summary: $PACKAGE_DIR/README.md"
