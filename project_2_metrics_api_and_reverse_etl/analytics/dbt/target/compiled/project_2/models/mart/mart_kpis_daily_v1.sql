-- mart_kpis_daily_v1: versioned KPI mart (v1)
-- Direct reference to project_1's mart_kpis_daily for versioning semantics

SELECT
  kpi_date,
  order_count,
  total_gmv,
  paid_gmv,
  active_users,
  payment_count,
  captured_amount,
  failed_payment_count,
  successful_payment_count,
  -- Calculated metrics
  CASE 
    WHEN order_count > 0 
    THEN CAST(captured_amount AS DOUBLE) / CAST(total_gmv AS DOUBLE) 
    ELSE 0 
  END AS payment_success_rate,
  CASE 
    WHEN payment_count > 0 
    THEN CAST(failed_payment_count AS DOUBLE) / CAST(payment_count AS DOUBLE) 
    ELSE 0 
  END AS payment_failure_rate,
  _computed_at,
  'v1' AS metric_version
FROM "iceberg"."mart_mart"."stg_kpis_daily"