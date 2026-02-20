# Airflow DAGs (P1/P2/P3 Shared)

This directory is automatically populated by `setup.ps1`, aggregating DAG files from all three projects:

- **Project 1**: backfill, reconciliation, quality_gate_cdc, maintenance_iceberg
- **Project 2**: metric_publish_gate
- **Project 3**: quality_gate_enforcement

After first running `.\setup.ps1`, DAGs will be copied from each project's `orchestration/airflow/dags/` to this directory for Airflow to load.
