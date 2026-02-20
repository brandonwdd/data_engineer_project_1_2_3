-- int_payments: business logic layer for payments.
-- Payment success logic, failure reason normalization.

SELECT
  payment_id,
  order_id,
  COALESCE(amount, 0) AS amount,
  CASE
    WHEN status IN ('created', 'authorized', 'captured', 'failed', 'refunded', 'cancelled') THEN status
    ELSE 'unknown'
  END AS status,
  failure_reason,
  updated_at,
  _bronze_event_uid,
  _bronze_ordering_key,
  _bronze_ts_ms,
  _silver_updated_at
FROM {{ ref('stg_payments') }}
WHERE amount >= 0  -- Business rule: amount must be non-negative
