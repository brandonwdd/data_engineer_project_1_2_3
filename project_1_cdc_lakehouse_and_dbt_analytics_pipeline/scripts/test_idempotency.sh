#!/bin/bash
# test_idempotency.sh: Idempotency test - run N times, verify KPI checksum unchanged
# Usage: ./scripts/test_idempotency.sh [N=3]
# Output: evidence/validation/idempotency_test_YYYY-MM-DD_HHMMSS.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$PROJECT_ROOT/evidence/validation"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
REPORT_FILE="$EVIDENCE_DIR/idempotency_test_${TIMESTAMP}.md"
PLATFORM_DIR="$PROJECT_ROOT/platform/local"

# Default: 3 runs
N_RUNS=${1:-3}

mkdir -p "$EVIDENCE_DIR"

echo "=== Idempotency Test ===" > "$REPORT_FILE"
echo "Test time: $(date -Iseconds)" >> "$REPORT_FILE"
echo "Number of runs: $N_RUNS" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Check environment
if ! docker ps | grep -q minio; then
    echo "[FAIL] Error: MinIO not running, start environment first" | tee -a "$REPORT_FILE"
    echo "Run: cd $PLATFORM_DIR && docker compose --profile bronze up -d" | tee -a "$REPORT_FILE"
    exit 1
fi

# Generate test data window
echo "## Step 1: Generate test data window" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

docker exec -i postgres psql -U postgres -d project1 <<SQL | tee -a "$REPORT_FILE"
-- Clean previous test data
DELETE FROM public.orders WHERE order_id >= 9000;
DELETE FROM public.users WHERE user_id >= 9000;

-- Insert test data
INSERT INTO public.users(user_id, email, status, created_at, updated_at)
VALUES (9001, 'idempotency_test_1@test.com', 'active', now(), now()),
       (9002, 'idempotency_test_2@test.com', 'active', now(), now()),
       (9003, 'idempotency_test_3@test.com', 'active', now(), now());

INSERT INTO public.orders(order_id, user_id, order_ts, status, total_amount, updated_at)
VALUES (9001, 9001, now(), 'created', 100.00, now()),
       (9002, 9002, now(), 'paid', 200.00, now()),
       (9003, 9003, now(), 'paid', 300.00, now());
SQL

sleep 5

# Record initial state (Run 0)
echo "" >> "$REPORT_FILE"
echo "## Step 2: Record initial state (Run 0 - Baseline)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Run Bronze ingest (once)
echo "Running Bronze ingest..." | tee -a "$REPORT_FILE"
docker compose -f "$PLATFORM_DIR/docker-compose.yml" --profile bronze run --rm --name idemp-test-bronze-0 spark \
  spark-submit --master local[*] \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2,org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
  /app/streaming/spark/bronze_ingest/ingest_raw_cdc.py &
BRONZE_PID=$!
sleep 20
kill $BRONZE_PID 2>/dev/null || true
wait $BRONZE_PID 2>/dev/null || true

# Run Silver merge
echo "Running Silver merge..." | tee -a "$REPORT_FILE"
docker compose -f "$PLATFORM_DIR/docker-compose.yml" --profile bronze run --rm --name idemp-test-silver-0 spark \
  spark-submit --master local[*] \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
  /app/streaming/spark/silver_merge/merge_silver.py || true

# Get initial checksum
python3 <<'PYTHON_EOF' | tee -a "$REPORT_FILE"
import sys
import os
sys.path.insert(0, os.environ.get("PROJECT_ROOT", "/app"))

from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("idempotency-baseline") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.iceberg.type", "hadoop") \
    .config("spark.sql.catalog.iceberg.warehouse", "s3a://warehouse/iceberg") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.secret.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .getOrCreate()

try:
    # Silver checksum
    silver_orders = spark.table("iceberg.silver.orders")
    silver_count = silver_orders.count()
    silver_total = silver_orders.filter("order_id >= 9000").agg({"total_amount": "sum"}).collect()[0][0] or 0
    
    # Gold checksum (if available)
    try:
        kpis = spark.table("iceberg.mart.mart_kpis_daily")
        gold_gmv = kpis.agg({"total_gmv": "sum"}).collect()[0][0] or 0
        gold_count = kpis.agg({"order_count": "sum"}).collect()[0][0] or 0
    except:
        gold_gmv = None
        gold_count = None
    
    print(f"Run 0 (Baseline):")
    print(f"  Silver orders count: {silver_count}")
    print(f"  Silver test orders total_amount: {silver_total}")
    if gold_gmv is not None:
        print(f"  Gold total_gmv: {gold_gmv}")
        print(f"  Gold order_count: {gold_count}")
except Exception as e:
    print(f"Error: {e}")

spark.stop()
PYTHON_EOF

# Repeat N times
echo "" >> "$REPORT_FILE"
echo "## Step 3: Repeat Silver merge $N_RUNS times" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

declare -a checksums=()

for i in $(seq 1 $N_RUNS); do
    echo "--- Run $i ---" | tee -a "$REPORT_FILE"
    
    # Re-run Silver merge (simulate replay)
    docker compose -f "$PLATFORM_DIR/docker-compose.yml" --profile bronze run --rm --name "idemp-test-silver-$i" spark \
      spark-submit --master local[*] \
      --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
      /app/streaming/spark/silver_merge/merge_silver.py || true
    
    # Get checksum
    CHECKSUM=$(python3 <<'PYTHON_EOF'
import sys
import os
import json
sys.path.insert(0, os.environ.get("PROJECT_ROOT", "/app"))

from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("idempotency-check") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.iceberg.type", "hadoop") \
    .config("spark.sql.catalog.iceberg.warehouse", "s3a://warehouse/iceberg") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.secret.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .getOrCreate()

try:
    silver_orders = spark.table("iceberg.silver.orders")
    silver_count = silver_orders.count()
    silver_total = silver_orders.filter("order_id >= 9000").agg({"total_amount": "sum"}).collect()[0][0] or 0
    
    result = {
        "silver_count": silver_count,
        "silver_total": float(silver_total) if silver_total else 0.0
    }
    
    try:
        kpis = spark.table("iceberg.mart.mart_kpis_daily")
        gold_gmv = kpis.agg({"total_gmv": "sum"}).collect()[0][0] or 0
        gold_count = kpis.agg({"order_count": "sum"}).collect()[0][0] or 0
        result["gold_gmv"] = float(gold_gmv) if gold_gmv else 0.0
        result["gold_count"] = gold_count
    except:
        result["gold_gmv"] = None
        result["gold_count"] = None
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))

spark.stop()
PYTHON_EOF
)
    
    checksums+=("$CHECKSUM")
    echo "Run $i checksum: $CHECKSUM" | tee -a "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
done

# Verify checksum consistency
echo "## Step 4: Verify checksum consistency" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Parse and compare checksums
python3 <<'PYTHON_EOF'
import sys
import json

checksums_str = sys.argv[1].split('\n')[:-1]  # Remove last empty line
checksums = [json.loads(c) for c in checksums_str if c.strip()]

if len(checksums) < 2:
    print("[FAIL] Error: Need at least 2 runs for comparison")
    sys.exit(1)

# Compare all checksums
all_match = True
baseline = checksums[0]

for i, checksum in enumerate(checksums[1:], start=1):
    if checksum.get("silver_count") != baseline.get("silver_count"):
        print(f"[FAIL] Run {i+1} silver_count mismatch: {checksum.get('silver_count')} != {baseline.get('silver_count')}")
        all_match = False
    
    if abs(checksum.get("silver_total", 0) - baseline.get("silver_total", 0)) > 0.01:
        print(f"[FAIL] Run {i+1} silver_total mismatch: {checksum.get('silver_total')} != {baseline.get('silver_total')}")
        all_match = False
    
    if checksum.get("gold_gmv") is not None and baseline.get("gold_gmv") is not None:
        if abs(checksum.get("gold_gmv", 0) - baseline.get("gold_gmv", 0)) > 0.01:
            print(f"[FAIL] Run {i+1} gold_gmv mismatch: {checksum.get('gold_gmv')} != {baseline.get('gold_gmv')}")
            all_match = False

if all_match:
    print("[OK] All checksums match, idempotency test passed!")
    sys.exit(0)
else:
    print("[FAIL] Checksums mismatch, idempotency test failed!")
    sys.exit(1)
PYTHON_EOF
"$(printf '%s\n' "${checksums[@]}")" | tee -a "$REPORT_FILE"

EXIT_CODE=$?

echo "" >> "$REPORT_FILE"
echo "## Test Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
if [ $EXIT_CODE -eq 0 ]; then
    echo "[OK] Idempotency test passed: repeated $N_RUNS times, checksum unchanged" >> "$REPORT_FILE"
    echo "[OK] Idempotency test passed!"
else
    echo "[FAIL] Idempotency test failed: checksum mismatch" >> "$REPORT_FILE"
    echo "[FAIL] Idempotency test failed, see: $REPORT_FILE"
fi

exit $EXIT_CODE
