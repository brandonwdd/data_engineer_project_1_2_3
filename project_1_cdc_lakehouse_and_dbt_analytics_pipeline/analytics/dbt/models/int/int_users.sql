-- int_users: business logic layer for users.
-- Normalize status enum, handle deleted users.

SELECT
  user_id,
  email,
  CASE
    WHEN status IN ('active', 'blocked', 'deleted') THEN status
    ELSE 'unknown'
  END AS status,
  created_at,
  updated_at,
  _bronze_event_uid,
  _bronze_ordering_key,
  _bronze_ts_ms,
  _silver_updated_at
FROM {{ ref('stg_users') }}
WHERE status != 'deleted'  -- Filter out soft-deleted users in int layer
