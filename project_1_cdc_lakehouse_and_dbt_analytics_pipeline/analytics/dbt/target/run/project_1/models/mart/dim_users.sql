
  
    

    create table "iceberg"."mart_mart"."dim_users__dbt_tmp"
      
      
    as (
      -- dim_users: user dimension table (from int_users).
-- One row per active user.

SELECT
  user_id,
  email,
  status,
  created_at,
  updated_at,
  _silver_updated_at AS _last_updated_at
FROM "iceberg"."mart_int"."int_users"
    );

  