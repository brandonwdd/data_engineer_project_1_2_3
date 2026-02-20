# Reconciliation Artifacts

This directory stores reconciliation outputs for CDC demos.

Each demo run should generate:
- Bronze CDC event counts by topic/partition
- Silver primary key row counts and uniqueness checks
- Gold KPI checksums (e.g., SUM(total_amount), COUNT(order_id))

Purpose:
- Prove no data loss after job restarts
- Prove idempotency after Kafka replay
- Prove deterministic results across reprocessing
