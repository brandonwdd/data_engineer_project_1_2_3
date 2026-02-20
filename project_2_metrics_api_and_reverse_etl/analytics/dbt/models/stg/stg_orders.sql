-- stg_orders: staging layer that directly references project_1's fct_orders

SELECT
  order_id,
  user_id,
  order_ts,
  status,
  total_amount,
  updated_at,
  paid_amount,
  is_cancelled,
  _last_updated_at
FROM iceberg.mart_mart.fct_orders
