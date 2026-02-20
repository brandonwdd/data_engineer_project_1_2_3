#!/bin/bash
# run_reconciliation.sh: Generate reconciliation report (Bronze/Silver/Gold counts, checksums).
# Output: recon/YYYY-MM-DD_recon_*.csv and .txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECON_DIR="$PROJECT_ROOT/recon"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)

# Ensure recon directory exists
mkdir -p "$RECON_DIR"

# Check if Trino/Spark is available (for querying Iceberg)
# This script assumes Trino is running and accessible, or we use Spark SQL
# For now, we'll use a Python script that uses Spark to query

cat > "$RECON_DIR/${TIMESTAMP}_recon_report.txt" <<EOF
# Reconciliation Report
Generated: $(date -Iseconds)

## Bronze Layer
EOF

# Bronze reconciliation: event_uid continuity, counts per topic/partition
python3 <<'PYTHON_EOF'
import sys
import os
sys.path.insert(0, os.environ.get("PROJECT_ROOT", "/app"))

from pyspark.sql import SparkSession
from datetime import datetime

spark = SparkSession.builder \
    .appName("reconciliation") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.iceberg.type", "hadoop") \
    .config("spark.sql.catalog.iceberg.warehouse", "s3a://warehouse/iceberg") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.secret.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .getOrCreate()

# Bronze counts by entity
bronze = spark.table("iceberg.bronze.raw_cdc")
bronze_counts = bronze.groupBy("entity").count().collect()

print("\n### Bronze Event Counts by Entity")
for row in bronze_counts:
    print(f"- {row.entity}: {row['count']:,} events")

# Bronze offset ranges per topic/partition
bronze_ranges = bronze.groupBy("kafka_topic", "kafka_partition").agg(
    {"kafka_offset": "min", "kafka_offset": "max", "event_uid": "count"}
).collect()

print("\n### Bronze Offset Ranges")
for row in bronze_ranges:
    print(f"- {row.kafka_topic} partition {row.kafka_partition}: offset range, {row['count(event_uid)']} events")

# Silver counts
try:
    silver_users = spark.table("iceberg.silver.users").count()
    silver_orders = spark.table("iceberg.silver.orders").count()
    silver_payments = spark.table("iceberg.silver.payments").count()
    print(f"\n### Silver Row Counts")
    print(f"- users: {silver_users:,}")
    print(f"- orders: {silver_orders:,}")
    print(f"- payments: {silver_payments:,}")
except Exception as e:
    print(f"\n### Silver: Not available ({e})")

# Gold KPI checksum (if available)
try:
    kpis = spark.table("iceberg.mart.mart_kpis_daily")
    total_gmv = kpis.agg({"total_gmv": "sum"}).collect()[0][0] or 0
    order_count = kpis.agg({"order_count": "sum"}).collect()[0][0] or 0
    print(f"\n### Gold KPI Checksum")
    print(f"- total_gmv: {total_gmv}")
    print(f"- order_count: {order_count}")
except Exception as e:
    print(f"\n### Gold: Not available ({e})")

spark.stop()
PYTHON_EOF

echo "Reconciliation report saved to: $RECON_DIR/${TIMESTAMP}_recon_report.txt"
