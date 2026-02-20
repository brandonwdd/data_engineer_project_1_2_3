
  
    

    create table "iceberg"."mart_stg"."stg_users__dbt_tmp"
      
      
    as (
      -- stg_users: staging layer for users (from Silver).
-- Cleansing: type casting, null handling, enum normalization.

SELECT
  user_id,
  CAST(email AS VARCHAR) AS email,
  CAST(status AS VARCHAR) AS status,
  CAST(created_at AS TIMESTAMP) AS created_at,
  CAST(updated_at AS TIMESTAMP) AS updated_at,
  CAST(_bronze_event_uid AS VARCHAR) AS _bronze_event_uid,
  CAST(_bronze_ordering_key AS VARCHAR) AS _bronze_ordering_key,
  CAST(_bronze_ts_ms AS BIGINT) AS _bronze_ts_ms,
  CAST(_silver_updated_at AS TIMESTAMP) AS _silver_updated_at
FROM iceberg.silver.users
    );

  