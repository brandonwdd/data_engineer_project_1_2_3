-- Silver payments: entity table with idempotent upserts (SCD1).
-- One row per payment_id; latest version by ordering_key.
-- Supports delete (op='d' removes the row).

CREATE TABLE IF NOT EXISTS iceberg.silver.payments (
  payment_id     BIGINT   NOT NULL,
  order_id       BIGINT   NOT NULL,
  amount         DECIMAL(18,2),
  status         STRING,
  failure_reason STRING,
  updated_at      TIMESTAMP,
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
