# Lakehouse / Iceberg (Project 1)

Iceberg catalog, table DDL, and maintenance for the CDC Lakehouse.

## Catalog

- **Type**: Hadoop
- **Warehouse**: `s3a://warehouse/iceberg` (MinIO) or `s3://...` (AWS)
- **Config**: Set via Spark in Bronze/Silver jobs (`spark.sql.catalog.iceberg.*`).

## Tables

- **`bronze.raw_cdc`**: Append-only CDC events from Kafka (Debezium).  
  - `event_uid`, `entity`, `entity_key`, `ordering_key`, Kafka metadata, envelope (`op`, `ts_ms`, `source`, `before`, `after`), `ingest_time`.  
  - Partitioned by `event_date` (from `ts_ms`).

## DDL

See `ddl/bronze_raw_cdc.sql`. Create via Spark SQL (or Trino) before running Bronze ingest.

## Maintenance

Airflow DAG `maintenance_iceberg` (TODO): compact, expire snapshots, remove orphans.
