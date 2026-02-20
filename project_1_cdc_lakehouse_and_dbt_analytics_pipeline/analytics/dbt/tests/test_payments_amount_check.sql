-- Custom test: payments success amount <= orders total amount
-- This validates business logic: captured payments should not exceed order total.

SELECT
  o.order_id,
  o.total_amount AS order_total,
  SUM(p.captured_amount) AS total_captured
FROM {{ ref('fct_orders') }} o
LEFT JOIN {{ ref('fct_payments') }} p ON o.order_id = p.order_id
GROUP BY o.order_id, o.total_amount
HAVING SUM(p.captured_amount) > o.total_amount
