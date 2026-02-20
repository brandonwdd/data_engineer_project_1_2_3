# Replay and Backfill Strategy

## Kafka Replay
- Reset consumer group offsets by time or offset
- Re-run Bronze ingestion
- Validate idempotency in Silver

## Lakehouse Replay
- Reprocess Silver/Gold from Bronze
- Use Iceberg time travel for rollback

## When to Use Which
- Kafka replay: short window corrections
- Bronze replay: logic fixes or audits
