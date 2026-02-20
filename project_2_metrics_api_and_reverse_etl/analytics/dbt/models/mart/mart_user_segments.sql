-- mart_user_segments: user segmentation mart table
-- One row per user with current segment assignments

SELECT
  user_id,
  status,
  created_at,
  last_90d_gmv,
  is_churn_risk,
  is_active,
  value_segment,
  activity_segment,
  _computed_at,
  CURRENT_DATE AS segment_date
FROM {{ ref('int_user_segments') }}
