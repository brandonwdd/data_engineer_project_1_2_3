select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from "iceberg"."mart_mart_dbt_test__audit"."dbt_utils_accepted_range_stg_kpis_daily_total_gmv__True__0"
    
      
    ) dbt_internal_test