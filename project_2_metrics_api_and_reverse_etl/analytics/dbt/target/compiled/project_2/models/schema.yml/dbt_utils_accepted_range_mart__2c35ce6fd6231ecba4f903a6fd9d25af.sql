

with meet_condition as(
  select *
  from "iceberg"."mart_mart"."mart_kpis_daily_v1"
),

validation_errors as (
  select *
  from meet_condition
  where
    -- never true, defaults to an empty result set. Exists to ensure any combo of the `or` clauses below succeeds
    1 = 2
    -- records with a value >= min_value are permitted. The `not` flips this to find records that don't meet the rule.
    or not payment_success_rate >= 0
    -- records with a value <= max_value are permitted. The `not` flips this to find records that don't meet the rule.
    or not payment_success_rate <= 1
)

select *
from validation_errors

