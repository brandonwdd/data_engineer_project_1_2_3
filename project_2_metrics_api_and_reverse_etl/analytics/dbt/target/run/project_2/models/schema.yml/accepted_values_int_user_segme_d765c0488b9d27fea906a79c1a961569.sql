select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from "iceberg"."mart_mart_dbt_test__audit"."accepted_values_int_user_segme_d765c0488b9d27fea906a79c1a961569"
    
      
    ) dbt_internal_test