# Observability (Project 1)

## Datadog Monitoring

### Monitors (`monitors/datadog/monitors.yaml`)
- Kafka consumer lag (Bronze ingest)
- Spark job success rate
- Data freshness (Bronze/Silver)
- Completeness (Gold KPI partitions)
- dbt tests pass rate
- Airflow DAG success rate

### Dashboard (`dashboards/exports/dashboard.json`)
- Kafka consumer lag by topic
- End-to-end latency (P95)
- Data freshness (real-time)
- Completeness (partition count)
- Spark job success rate
- dbt tests pass rate
- Spark micro-batch duration
- Bronze event count by entity

## Metrics Collection

Metrics are sent to Datadog via:
- Spark metrics (via Datadog agent or Spark metrics sink)
- Kafka metrics (via Datadog Kafka integration)
- Airflow metrics (via Datadog Airflow integration)
- Custom metrics (via Datadog API from reconciliation scripts)

## Deployment

```bash
# Deploy monitors (via Datadog API)
datadog-cli monitors import monitors/datadog/monitors.yaml

# Import dashboard (via Datadog UI or API)
# Upload dashboards/exports/dashboard.json
```
