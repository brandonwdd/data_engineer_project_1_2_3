select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from "iceberg"."mart_mart_dbt_test__audit"."not_null_stg_payments_payment_id"
    
      
    ) dbt_internal_test