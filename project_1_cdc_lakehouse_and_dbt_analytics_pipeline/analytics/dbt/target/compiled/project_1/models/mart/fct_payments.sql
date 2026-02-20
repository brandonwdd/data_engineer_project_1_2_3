-- fct_payments: payments fact table (from int_payments).
-- One row per payment with success/failure metrics.

SELECT
  payment_id,
  order_id,
  amount,
  status,
  failure_reason,
  updated_at,
  CASE WHEN status = 'captured' THEN amount ELSE 0 END AS captured_amount,
  CASE WHEN status = 'failed' THEN 1 ELSE 0 END AS is_failed,
  _silver_updated_at AS _last_updated_at
FROM "iceberg"."mart_int"."int_payments"