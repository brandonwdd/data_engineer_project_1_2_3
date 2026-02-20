#!/bin/bash
# demo_failure_recovery.sh: Kill Spark job → recover → validate reconciliation.
# Demonstrates checkpoint-based recovery and data correctness.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM_DIR="$PROJECT_ROOT/platform/local"
RECON_DIR="$PROJECT_ROOT/recon"

echo "=== Demo 1: Failure Recovery ==="
echo "Step 1: Start Bronze ingest (background)..."
cd "$PLATFORM_DIR"
docker compose --profile bronze up -d minio minio-init
sleep 15

# Start Bronze in background, capture PID
docker compose --profile bronze run -d --name demo1-bronze spark > /dev/null 2>&1 || true
BRONZE_CONTAINER="demo1-bronze"
sleep 10

echo "Step 2: Generate some test data in Postgres..."
docker exec -i postgres psql -U postgres -d project1 <<SQL
INSERT INTO public.users(user_id, email, status, created_at, updated_at)
VALUES (100, 'demo1@test.com', 'active', now(), now()),
       (101, 'demo2@test.com', 'active', now(), now());

INSERT INTO public.orders(order_id, user_id, order_ts, status, total_amount, updated_at)
VALUES (1000, 100, now(), 'created', 99.99, now()),
       (1001, 101, now(), 'paid', 149.50, now());
SQL

sleep 5

echo "Step 3: Kill Bronze job..."
docker kill "$BRONZE_CONTAINER" 2>/dev/null || true
docker rm "$BRONZE_CONTAINER" 2>/dev/null || true

echo "Step 4: Record pre-recovery state..."
"$SCRIPT_DIR/run_reconciliation.sh" > "$RECON_DIR/demo1_pre_recovery.txt" 2>&1 || true

echo "Step 5: Restart Bronze (should resume from checkpoint)..."
docker compose --profile bronze run -d --name demo1-bronze-recovered spark > /dev/null 2>&1 || true
sleep 10

echo "Step 6: Run Silver merge..."
docker compose --profile bronze run --rm --name demo1-silver spark \
  spark-submit --master local[*] \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
  /app/streaming/spark/silver_merge/merge_silver.py || true

echo "Step 7: Post-recovery reconciliation..."
"$SCRIPT_DIR/run_reconciliation.sh" > "$RECON_DIR/demo1_post_recovery.txt" 2>&1 || true

echo "Step 8: Compare pre/post recovery..."
echo "=== Pre-recovery ==="
cat "$RECON_DIR/demo1_pre_recovery.txt" || echo "No pre-recovery data"
echo ""
echo "=== Post-recovery ==="
cat "$RECON_DIR/demo1_post_recovery.txt" || echo "No post-recovery data"

echo ""
echo "Demo 1 complete. Check reconciliation reports in $RECON_DIR/"
