# Architecture Overview

High-level flow:
Postgres -> Debezium -> Kafka -> Spark -> Iceberg -> Trino

Layers:
- Bronze: raw CDC events (append-only)
- Silver: entity tables with idempotent upserts
- Gold: analytics marts

Design goals:
- Deterministic ordering
- Replayability
- Idempotency
- Observability
