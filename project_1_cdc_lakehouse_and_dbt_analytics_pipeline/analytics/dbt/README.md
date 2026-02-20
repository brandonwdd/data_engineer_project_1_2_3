# dbt (Project 1) - Analytics Layer

## Structure

- **stg/**: Staging models (from Silver Iceberg tables)
  - `stg_users`, `stg_orders`, `stg_payments`
- **int/**: Intermediate models (business logic, normalization)
  - `int_users`, `int_orders`, `int_payments`
- **mart/**: Marts (fact/dimension tables, KPIs)
  - `dim_users`, `fct_orders`, `fct_payments`, `mart_kpis_daily`

## Tests

- Schema tests: `not_null`, `unique`, `relationships` (referential integrity)
- Custom tests: `test_payments_amount_check`, `test_kpi_completeness`

## Run

```bash
cd analytics/dbt
dbt deps  # Install dbt_utils, dbt_expectations
dbt run
dbt test
```
