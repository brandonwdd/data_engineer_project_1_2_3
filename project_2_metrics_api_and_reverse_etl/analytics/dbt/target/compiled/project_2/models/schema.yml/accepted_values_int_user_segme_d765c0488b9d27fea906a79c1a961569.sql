
    
    

with all_values as (

    select
        value_segment as value_field,
        count(*) as n_records

    from "iceberg"."mart_mart"."int_user_segments"
    group by value_segment

)

select *
from all_values
where value_field not in (
    'high_value','medium_value','low_value'
)


