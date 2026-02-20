
    
    

with all_values as (

    select
        activity_segment as value_field,
        count(*) as n_records

    from "iceberg"."mart_mart"."int_user_segments"
    group by activity_segment

)

select *
from all_values
where value_field not in (
    'churn_risk','active','dormant'
)


