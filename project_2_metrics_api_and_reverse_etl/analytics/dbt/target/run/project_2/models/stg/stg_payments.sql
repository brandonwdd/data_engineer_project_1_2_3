
  
    

    create table "iceberg"."mart_mart"."stg_payments__dbt_tmp"
      
      
    as (
      -- stg_payments: staging layer that directly references project_1's fct_payments

SELECT
  payment_id,
  order_id,
  amount,
  status,
  failure_reason,
  updated_at,
  captured_amount,
  is_failed,
  _last_updated_at
FROM iceberg.mart_mart.fct_payments
    );

  