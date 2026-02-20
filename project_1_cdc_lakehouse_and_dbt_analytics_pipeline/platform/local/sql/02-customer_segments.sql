-- Project 2 Reverse ETL target (run once in project1 DB: psql -h localhost -U postgres -d project1 -f 02-customer_segments.sql)
CREATE TABLE IF NOT EXISTS public.customer_segments (
    user_id VARCHAR NOT NULL,
    segment_date DATE NOT NULL,
    value_segment VARCHAR,
    activity_segment VARCHAR,
    last_90d_gmv DECIMAL(18, 2),
    is_churn_risk INTEGER,
    is_active INTEGER,
    source_run_id VARCHAR NOT NULL,
    last_updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, segment_date)
);
