-- stg_users: staging layer that directly references project_1's dim_users

SELECT
  user_id,
  email,
  status,
  created_at,
  updated_at,
  _last_updated_at
FROM iceberg.mart_mart.dim_users
