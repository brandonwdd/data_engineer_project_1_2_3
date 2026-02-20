#!/bin/bash
# demo_schema_evolution.sh: Add column to OLTP → Debezium captures → Spark/Iceberg compatible.
# Demonstrates backward-compatible schema evolution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM_DIR="$PROJECT_ROOT/platform/local"

echo "=== Demo 3: Schema Evolution ==="

echo "Step 1: Record current schema..."
docker exec postgres psql -U postgres -d project1 -c "\d public.orders" > "$PROJECT_ROOT/recon/demo3_schema_before.txt"

echo "Step 2: Add new column to OLTP (backward compatible: nullable)..."
docker exec -i postgres psql -U postgres -d project1 <<SQL
ALTER TABLE public.orders ADD COLUMN shipping_address TEXT;
COMMENT ON COLUMN public.orders.shipping_address IS 'New field added for schema evolution demo';
SQL

echo "Step 3: Insert row with new field..."
docker exec -i postgres psql -U postgres -d project1 <<SQL
INSERT INTO public.orders(order_id, user_id, order_ts, status, total_amount, updated_at, shipping_address)
VALUES (3000, 1, now(), 'created', 250.00, now(), '123 Main St, City, State');
SQL

sleep 5

echo "Step 4: Verify Debezium captured new field..."
docker exec kafka sh -lc \
  "kafka-console-consumer --bootstrap-server kafka:9092 \
   --topic dbserver_docker.public.orders --from-beginning --max-messages 1" | \
   grep -o '"shipping_address"' || echo "New field not yet in Kafka (may need connector restart)"

echo "Step 5: Add column to Iceberg Silver table (if not exists)..."
docker compose --profile bronze run --rm --name demo3-iceberg-alter spark \
  spark-sql --master local[*] \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
  -e "ALTER TABLE iceberg.silver.orders ADD COLUMN IF NOT EXISTS shipping_address STRING;" || true

echo "Step 6: Re-run Silver merge (should handle new field)..."
docker compose --profile bronze run --rm --name demo3-silver-merge spark \
  spark-submit --master local[*] \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
  /app/streaming/spark/silver_merge/merge_silver.py || true

echo "Step 7: Verify Silver table has new column..."
docker compose --profile bronze run --rm --name demo3-verify spark \
  spark-sql --master local[*] \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
  -e "DESCRIBE iceberg.silver.orders;" || true

echo ""
echo "Demo 3 complete. Schema evolution validated if new column appears in Silver."
