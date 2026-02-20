-- Silver users: entity table with idempotent upserts (SCD1).
-- One row per user_id; latest version by ordering_key.
-- Run via Spark SQL with Iceberg catalog "iceberg", namespace "silver".

CREATE NAMESPACE IF NOT EXISTS iceberg.silver;

CREATE TABLE IF NOT EXISTS iceberg.silver.users (
  user_id     BIGINT   NOT NULL,
  email       STRING,
  status      STRING,
  created_at  TIMESTAMP,
  updated_at  TIMESTAMP,
  -- Audit fields
  _bronze_event_uid STRING COMMENT 'Latest event_uid from Bronze',
  _bronze_ordering_key STRING COMMENT 'Latest ordering_key from Bronze',
  _bronze_ts_ms BIGINT COMMENT 'Latest ts_ms from Bronze',
  _silver_updated_at TIMESTAMP NOT NULL COMMENT 'When this Silver row was last updated'
)
USING iceberg
PARTITIONED BY (days(_silver_updated_at))
TBLPROPERTIES (
  'format-version' = '2',
  'write.parquet.compression-codec' = 'snappy',
  'write.metadata.delete-after-commit.enabled' = 'true',
  'write.metadata.previous-versions-max' = '5'
);
