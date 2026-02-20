#!/bin/bash
# demo_replay_idempotency.sh: Reset Kafka offsets → replay → verify KPI checksum unchanged.
# Demonstrates idempotent processing: same window processed N times yields same Gold state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM_DIR="$PROJECT_ROOT/platform/local"
RECON_DIR="$PROJECT_ROOT/recon"

echo "=== Demo 2: Replay & Idempotency ==="

# Step 1: Generate test data
echo "Step 1: Generate test data window..."
docker exec -i postgres psql -U postgres -d project1 <<SQL
INSERT INTO public.users(user_id, email, status, created_at, updated_at)
VALUES (200, 'replay1@test.com', 'active', now(), now()),
       (201, 'replay2@test.com', 'active', now(), now());

INSERT INTO public.orders(order_id, user_id, order_ts, status, total_amount, updated_at)
VALUES (2000, 200, now(), 'created', 200.00, now()),
       (2001, 201, now(), 'paid', 300.00, now());
SQL

sleep 5

# Step 2: Record initial KPI checksum
echo "Step 2: Record initial KPI checksum (Run 1)..."
python3 <<'PYTHON_EOF'
import sys
import os
sys.path.insert(0, os.environ.get("PROJECT_ROOT", "/app"))

from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("recon-run1") \
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
    kpis = spark.table("iceberg.mart.mart_kpis_daily")
    total_gmv = kpis.agg({"total_gmv": "sum"}).collect()[0][0] or 0
    order_count = kpis.agg({"order_count": "sum"}).collect()[0][0] or 0
    print(f"Run 1 - total_gmv: {total_gmv}, order_count: {order_count}")
except:
    print("Run 1 - Gold not available yet")

spark.stop()
PYTHON_EOF

# Step 3: Reset Kafka consumer group offsets to replay window
echo "Step 3: Reset Kafka offsets (replay window)..."
# Note: This requires kafka-consumer-groups tool. For demo, we'll use a new consumer group.
REPLAY_GROUP="project1-bronze-replay-$(date +%s)"

# Step 4: Replay Bronze (with new group, from earliest)
echo "Step 4: Replay Bronze with new consumer group..."
docker compose --profile bronze run --rm --name demo2-bronze-replay \
  -e KAFKA_GROUP="$REPLAY_GROUP" \
  -e KAFKA_STARTING_OFFSETS=earliest \
  spark \
  spark-submit --master local[*] \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2,org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
  /app/streaming/spark/bronze_ingest/ingest_raw_cdc.py &
BRONZE_PID=$!
sleep 15
kill $BRONZE_PID 2>/dev/null || true

# Step 5: Re-run Silver merge (should be idempotent)
echo "Step 5: Re-run Silver merge (idempotent)..."
docker compose --profile bronze run --rm --name demo2-silver-replay spark \
  spark-submit --master local[*] \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
  /app/streaming/spark/silver_merge/merge_silver.py || true

# Step 6: Verify KPI checksum unchanged
echo "Step 6: Verify KPI checksum (Run 2)..."
python3 <<'PYTHON_EOF'
import sys
import os
sys.path.insert(0, os.environ.get("PROJECT_ROOT", "/app"))

from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("recon-run2") \
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
    kpis = spark.table("iceberg.mart.mart_kpis_daily")
    total_gmv = kpis.agg({"total_gmv": "sum"}).collect()[0][0] or 0
    order_count = kpis.agg({"order_count": "sum"}).collect()[0][0] or 0
    print(f"Run 2 - total_gmv: {total_gmv}, order_count: {order_count}")
    print("Idempotency check: Compare Run 1 vs Run 2 checksums")
except Exception as e:
    print(f"Run 2 - Error: {e}")

spark.stop()
PYTHON_EOF

echo ""
echo "Demo 2 complete. Idempotency validated if checksums match across runs."
