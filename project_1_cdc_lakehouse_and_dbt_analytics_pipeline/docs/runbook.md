# Runbook

## Common Incidents

1) Kafka consumer lag spike
- Check consumer group lag
- Scale Spark job or increase partitions

2) Spark job failure
- Inspect logs
- Restart job
- Validate Bronze event continuity
- Run reconciliation

3) Data freshness SLA breach
- Check ingestion latency
- Check Silver merge backlog
- Trigger backfill if needed
