
  
    

    create table "iceberg"."mart_mart"."stg_kpis_daily__dbt_tmp"
      
      
    as (
      -- stg_kpis_daily: staging layer that directly references project_1's mart_kpis_daily
-- This ensures single source of truth for KPIs

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
  _computed_at
FROM iceberg.mart_mart.mart_kpis_daily
    );

  