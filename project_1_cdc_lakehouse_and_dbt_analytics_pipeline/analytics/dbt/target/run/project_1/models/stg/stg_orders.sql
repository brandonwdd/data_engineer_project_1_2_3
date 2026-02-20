
  
    

    create table "iceberg"."mart_stg"."stg_orders__dbt_tmp"
      
      
    as (
      -- stg_orders: staging layer for orders (from Silver).
-- Cleansing: type casting, null handling, enum normalization.

SELECT
  order_id,
  CAST(user_id AS BIGINT) AS user_id,
  CAST(order_ts AS TIMESTAMP) AS order_ts,
  CAST(status AS VARCHAR) AS status,
  CAST(total_amount AS DECIMAL(18,2)) AS total_amount,
  CAST(updated_at AS TIMESTAMP) AS updated_at,
  CAST(_bronze_event_uid AS VARCHAR) AS _bronze_event_uid,
  CAST(_bronze_ordering_key AS VARCHAR) AS _bronze_ordering_key,
  CAST(_bronze_ts_ms AS BIGINT) AS _bronze_ts_ms,
  CAST(_silver_updated_at AS TIMESTAMP) AS _silver_updated_at
FROM iceberg.silver.orders
    );

  