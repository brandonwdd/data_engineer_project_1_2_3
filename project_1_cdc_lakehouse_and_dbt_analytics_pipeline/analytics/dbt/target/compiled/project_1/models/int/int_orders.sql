-- int_orders: business logic layer for orders.
-- Order state machine, payment success logic, deduplication.

SELECT
  order_id,
  user_id,
  order_ts,
  CASE
    WHEN status IN ('created', 'paid', 'shipped', 'cancelled', 'refunded') THEN status
    ELSE 'unknown'
  END AS status,
  COALESCE(total_amount, 0) AS total_amount,
  updated_at,
  _bronze_event_uid,
  _bronze_ordering_key,
  _bronze_ts_ms,
  _silver_updated_at
FROM "iceberg"."mart_stg"."stg_orders"
WHERE total_amount >= 0  -- Business rule: amount must be non-negative