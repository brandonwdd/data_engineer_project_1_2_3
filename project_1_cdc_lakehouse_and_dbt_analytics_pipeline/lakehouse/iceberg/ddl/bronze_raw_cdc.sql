-- Bronze raw_cdc: append-only CDC events (Debezium envelope + Kafka metadata + audit keys).
-- Run via Spark SQL with Iceberg catalog "iceberg", namespace "bronze".
-- Warehouse: s3a://warehouse/iceberg (MinIO) or S3.

CREATE DATABASE IF NOT EXISTS iceberg.bronze;

CREATE TABLE IF NOT EXISTS iceberg.bronze.raw_cdc (
  event_uid       STRING   NOT NULL COMMENT 'Audit unique: topic|partition|offset',
  entity          STRING   NOT NULL COMMENT 'Entity name: users|orders|payments',
  entity_key      STRING   NOT NULL COMMENT 'Business PK value(s)',
  ordering_key    STRING   NOT NULL COMMENT 'Deterministic sort: lsn|updated_at|partition|offset',
  kafka_topic     STRING   NOT NULL,
  kafka_partition INT      NOT NULL,
  kafka_offset    BIGINT   NOT NULL,
  kafka_timestamp BIGINT,
  op              STRING   NOT NULL,
  ts_ms           BIGINT   NOT NULL,
  source          STRING   COMMENT 'Debezium source JSON',
  before          STRING   COMMENT 'before payload JSON',
  after           STRING   COMMENT 'after payload JSON',
  ingest_time     TIMESTAMP NOT NULL
)
USING iceberg
PARTITIONED BY (days(ingest_time))
TBLPROPERTIES (
  'format-version' = '2',
  'write.parquet.compression-codec' = 'snappy'
);
