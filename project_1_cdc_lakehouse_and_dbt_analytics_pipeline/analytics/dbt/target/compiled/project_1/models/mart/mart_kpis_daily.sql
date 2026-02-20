-- mart_kpis_daily: daily KPI aggregation.
-- GMV, order count, payment success rate, etc.

SELECT
  DATE(order_ts) AS kpi_date,
  COUNT(DISTINCT o.order_id) AS order_count,
  SUM(o.total_amount) AS total_gmv,
  SUM(o.paid_amount) AS paid_gmv,
  COUNT(DISTINCT o.user_id) AS active_users,
  COUNT(DISTINCT p.payment_id) AS payment_count,
  SUM(p.captured_amount) AS captured_amount,
  SUM(p.is_failed) AS failed_payment_count,
  COUNT(DISTINCT CASE WHEN p.status = 'captured' THEN p.payment_id END) AS successful_payment_count,
  CURRENT_TIMESTAMP AS _computed_at
FROM "iceberg"."mart_mart"."fct_orders" o
LEFT JOIN "iceberg"."mart_mart"."fct_payments" p ON o.order_id = p.order_id
GROUP BY DATE(order_ts)