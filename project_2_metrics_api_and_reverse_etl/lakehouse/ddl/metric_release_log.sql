-- metric_release_log: tracks metric version releases for governance
-- This table enables traceability of metric changes

CREATE TABLE IF NOT EXISTS iceberg.mart_mart.metric_release_log (
  release_id VARCHAR,
  metric_version VARCHAR NOT NULL,
  git_commit VARCHAR,
  git_branch VARCHAR,
  released_by VARCHAR,
  released_at TIMESTAMP NOT NULL,
  dbt_tests_passed BOOLEAN NOT NULL,
  dbt_tests_summary VARCHAR,
  completeness_check_passed BOOLEAN NOT NULL,
  data_range_start DATE,
  data_range_end DATE,
  release_notes VARCHAR,
  PRIMARY KEY (release_id)
)
WITH (
  format = 'PARQUET',
  partitioning = ARRAY['metric_version']
);