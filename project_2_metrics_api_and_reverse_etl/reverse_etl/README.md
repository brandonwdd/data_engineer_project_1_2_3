# Reverse ETL

## Overview

Reverse ETL writes Project 2 metrics and user-segment data back to downstream systems, closing the data loop.

Two write paths:

1. **Postgres**: upsert to CRM/operational systems
2. **Kafka**: publish to real-time activation systems

## Design

- **Idempotent**: Safe to retry; no duplicate data
- **Ordering**: Per-user ordering (Kafka keyed by user_id)
- **Traceable**: `source_run_id` for auditing

## Layout

```
reverse_etl/
├── postgres/
│   └── upsert_segments.py    # Postgres upsert
├── kafka/
│   └── publish_segments.py   # Kafka publish
├── requirements.txt
└── README.md
```

## Postgres Upsert

### Purpose

Upsert user segments into Postgres `customer_segments`.

### Usage

```bash
cd reverse_etl
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_DB=project1
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=postgres

python postgres/upsert_segments.py
```

### Target schema

```sql
CREATE TABLE customer_segments (
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
```

### Idempotency

Uses PostgreSQL `ON CONFLICT`:

```sql
INSERT INTO customer_segments (...)
VALUES (...)
ON CONFLICT (user_id, segment_date)
DO UPDATE SET
    value_segment = EXCLUDED.value_segment,
    ...
    source_run_id = EXCLUDED.source_run_id,
    last_updated_at = EXCLUDED.last_updated_at
```

- PK: `(user_id, segment_date)`
- Re-runs do not create duplicates
- Latest data overwritten

### Config

| Env var | Description | Default |
|---------|-------------|---------|
| `POSTGRES_HOST` | Postgres host | localhost |
| `POSTGRES_PORT` | Postgres port | 5432 |
| `POSTGRES_DB` | Database | project1 |
| `POSTGRES_USER` | User | postgres |
| `POSTGRES_PASSWORD` | Password | postgres |
| `SEGMENT_TABLE` | Target table | customer_segments |

## Kafka Publish

### Purpose

Publish user segments to Kafka `segment_updates` topic.

### Usage

```bash
cd reverse_etl
export KAFKA_BOOTSTRAP_SERVERS=localhost:9092
export SEGMENT_TOPIC=segment_updates

python kafka/publish_segments.py
```

### Topic

- **Topic**: `segment_updates` (configurable)
- **Key**: `user_id` (per-user ordering)
- **Value**: JSON

### Message format

```json
{
  "user_id": "123",
  "segment_date": "2026-01-15",
  "value_segment": "high_value",
  "activity_segment": "active",
  "last_90d_gmv": 1500.0,
  "is_churn_risk": 0,
  "is_active": 1,
  "source_run_id": "uuid-here",
  "published_at": "2026-01-15T10:00:00Z"
}
```

### Ordering

- Key: `user_id`
- Same user → same partition
- Order preserved per user

### Reliability

- `acks='all'`
- `enable_idempotence=True`
- `retries=3`
- `max_in_flight_requests_per_connection=1`

### Config

| Env var | Description | Default |
|---------|-------------|---------|
| `KAFKA_BOOTSTRAP_SERVERS` | Broker(s) | localhost:9092 |
| `SEGMENT_TOPIC` | Topic | segment_updates |

## Data source

Reverse ETL reads from Trino:

```sql
SELECT 
    user_id,
    segment_date,
    value_segment,
    activity_segment,
    last_90d_gmv,
    is_churn_risk,
    is_active
FROM iceberg.mart.mart_user_segments
WHERE segment_date = CURRENT_DATE
```

## Troubleshooting

### Postgres connection

1. Check Postgres is running
2. Verify host, port, user, password
3. Check network
4. Verify table exists (or auto-creation)

### Kafka publish

1. Check Kafka is running
2. Verify broker config
3. Ensure topic exists (create if needed)
4. Check network

### Data issues

1. Check Trino connection
2. Verify `mart_user_segments` exists
3. Verify data has been generated

## Monitoring

### Metrics

- **Success rate**: records processed / total
- **Retries**: failed retry count
- **Duration**: read → write

### Logs

- Success/failure counts
- Error details
- `source_run_id` for tracing

## Practices

1. **Batch**: Process multiple records per run
2. **Errors**: Log failures, support retry
3. **Idempotency**: Safe to retry
4. **Monitoring**: Success rate and duration
5. **Audit**: Use `source_run_id` for traceability

## References

- [Project 2 README](../README.md)
- [Architecture](../docs/architecture.md)
- [Runbook](../runbook/reverse_etl_failure.md)
