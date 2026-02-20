select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from "iceberg"."mart_mart_dbt_test__audit"."dbt_utils_accepted_range_mart__2c35ce6fd6231ecba4f903a6fd9d25af"
    
      
    ) dbt_internal_test