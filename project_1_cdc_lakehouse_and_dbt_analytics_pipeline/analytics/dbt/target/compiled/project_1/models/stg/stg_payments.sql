-- stg_payments: staging layer for payments (from Silver).
-- Cleansing: type casting, null handling, enum normalization.

SELECT
  payment_id,
  CAST(order_id AS BIGINT) AS order_id,
  CAST(amount AS DECIMAL(18,2)) AS amount,
  CAST(status AS VARCHAR) AS status,
  CAST(failure_reason AS VARCHAR) AS failure_reason,
  CAST(updated_at AS TIMESTAMP) AS updated_at,
  CAST(_bronze_event_uid AS VARCHAR) AS _bronze_event_uid,
  CAST(_bronze_ordering_key AS VARCHAR) AS _bronze_ordering_key,
  CAST(_bronze_ts_ms AS BIGINT) AS _bronze_ts_ms,
  CAST(_silver_updated_at AS TIMESTAMP) AS _silver_updated_at
FROM iceberg.silver.payments