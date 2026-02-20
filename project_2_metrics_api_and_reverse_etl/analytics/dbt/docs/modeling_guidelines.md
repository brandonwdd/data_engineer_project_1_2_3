# dbt Modeling Guidelines

Layers:
- stg: Raw field cleanup and normalization
- int: Business logic and deduplication
- mart: KPI marts and dimensions

Principles:
- One source of truth per metric
- Deterministic logic
- Test-driven modeling
