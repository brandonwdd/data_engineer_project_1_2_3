select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from "iceberg"."mart_mart_dbt_test__audit"."accepted_values_int_user_segme_dab2b2474d072c83a4ad90b704b01a74"
    
      
    ) dbt_internal_test