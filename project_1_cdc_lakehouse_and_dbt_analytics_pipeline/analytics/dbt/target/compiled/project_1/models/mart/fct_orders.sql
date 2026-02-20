-- fct_orders: orders fact table (from int_orders).
-- One row per order with business metrics.

SELECT
  order_id,
  user_id,
  order_ts,
  status,
  total_amount,
  updated_at,
  CASE WHEN status = 'paid' THEN total_amount ELSE 0 END AS paid_amount,
  CASE WHEN status IN ('cancelled', 'refunded') THEN 1 ELSE 0 END AS is_cancelled,
  _silver_updated_at AS _last_updated_at
FROM "iceberg"."mart_int"."int_orders"