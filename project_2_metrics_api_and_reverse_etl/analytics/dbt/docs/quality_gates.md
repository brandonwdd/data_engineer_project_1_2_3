# Data Quality Gates

All downstream publishing is blocked if:

- not_null tests fail
- unique tests fail
- referential integrity fails
- completeness checks fail

Quality gates are enforced in Airflow before:
- Metrics API publishing
- Reverse ETL execution
