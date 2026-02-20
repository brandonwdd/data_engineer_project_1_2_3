-- int_user_segments: business logic layer for user segmentation
-- Calculates user segments based on behavior and value

WITH user_metrics AS (
  SELECT
    u.user_id,
    u.status,
    u.created_at,
    -- High value: total GMV > 1000 in last 90 days
    COALESCE(SUM(CASE 
      WHEN o.order_ts >= CURRENT_DATE - INTERVAL '90' DAY 
      THEN o.total_amount 
      ELSE 0 
    END), 0) AS last_90d_gmv,
    -- Churn risk: no orders in last 30 days but had orders before
    CASE 
      WHEN MAX(o.order_ts) < CURRENT_DATE - INTERVAL '30' DAY 
        AND MAX(o.order_ts) IS NOT NULL
      THEN 1 
      ELSE 0 
    END AS is_churn_risk,
    -- Active: has order in last 7 days
    CASE 
      WHEN MAX(o.order_ts) >= CURRENT_DATE - INTERVAL '7' DAY 
      THEN 1 
      ELSE 0 
    END AS is_active
  FROM "iceberg"."mart_mart"."stg_users" u
  LEFT JOIN "iceberg"."mart_mart"."stg_orders" o ON u.user_id = o.user_id
  WHERE u.status = 'active'
  GROUP BY u.user_id, u.status, u.created_at
)
SELECT
  user_id,
  status,
  created_at,
  last_90d_gmv,
  is_churn_risk,
  is_active,
  CASE 
    WHEN last_90d_gmv >= 1000 THEN 'high_value'
    WHEN last_90d_gmv >= 500 THEN 'medium_value'
    ELSE 'low_value'
  END AS value_segment,
  CASE 
    WHEN is_churn_risk = 1 THEN 'churn_risk'
    WHEN is_active = 1 THEN 'active'
    ELSE 'dormant'
  END AS activity_segment,
  CURRENT_TIMESTAMP AS _computed_at
FROM user_metrics