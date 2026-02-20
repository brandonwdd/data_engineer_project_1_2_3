# Key Architecture Trade-offs

This document records major design decisions made for the CDC Lakehouse.

## 1) At-least-once Ingestion vs Exactly-once

Choice:
- At-least-once ingestion with idempotent Silver upserts  

Rationale:
- Simpler operational model  
- Easier recovery and replay  
- Deterministic results via ordering_key and merge semantics  

Cost:
- Requires careful idempotent merge logic  

Mitigation:
- Enforced deterministic ordering keys  
- Added reconciliation and checksum validation  

---

## 2) Bronze Append-only vs Direct Upserts

Choice:
- Bronze stores raw CDC events append-only  

Rationale:
- Full auditability  
- Supports replay and backfill  
- Simplifies debugging and incident analysis  

Cost:
- Higher storage usage  

Mitigation:
- Snapshot expiration and file compaction in maintenance jobs  

---

## 3) Spark Structured Streaming vs Flink

Choice:
- Spark Structured Streaming  

Rationale:
- Strong ecosystem integration  
- Easier Iceberg and batch unification  
- Operational familiarity  

Cost:
- Higher micro-batch latency vs true streaming  

Mitigation:
- SLA tuned to micro-batch semantics  
- Backpressure and scaling policies  

---

## 4) Iceberg vs Delta / Hudi

Choice:
- Apache Iceberg  

Rationale:
- Engine-agnostic (Spark, Trino)  
- Built-in time travel  
- Clean snapshot semantics  

Cost:
- Slightly more operational complexity  

Mitigation:
- Automated maintenance workflows  
- Snapshot expiration policies  

---

## 5) ordering_key Choice: lsn/txId First, Fallback When Missing

Choice:
- Primary: source.lsn (Postgres LSN)
- Fallback: after.updated_at + kafka.partition + kafka.offset

Rationale:
- LSN provides true transaction ordering
- Fallback ensures deterministic ordering even without LSN
- String concatenation preserves lexicographic ordering

Cost:
- Requires parsing source JSON
- Fallback may have lower precision

Mitigation:
- Contract defines priority clearly
- Validation ensures at least one component exists
- Ordering_key comparison in MERGE ensures idempotency

---

## 6) Kafka Replay vs Bronze Recompute

Choice:
- Both supported, choose based on scenario

When to use Kafka replay:
- Need to reprocess specific time window
- Testing new logic on historical data
- Debugging specific event sequence

When to use Bronze recompute:
- Logic change in Silver/Gold processing
- Need to avoid re-consuming Kafka (cost/performance)
- Audit trail from Bronze is sufficient

Rationale:
- Kafka replay: closer to source, tests full pipeline
- Bronze recompute: faster, avoids Kafka re-consumption

Cost:
- Kafka replay: higher cost, slower
- Bronze recompute: requires Bronze storage

Mitigation:
- Document decision tree in runbook
- Demo scripts show both approaches

---

## 7) Schema Evolution: Additive Backward-Compatible, Delete Requires Deprecate

Choice:
- Add: nullable or default (backward compatible)
- Delete: deprecate cycle (1-2 versions minimum)

Rationale:
- Backward compatibility prevents breaking consumers
- Deprecation cycle gives time for migration
- Production systems require gradual changes

Cost:
- Deprecation cycle adds complexity
- Need to maintain old fields temporarily

Mitigation:
- Contract defines evolution policy
- dbt models handle missing fields gracefully
- Runbook documents deprecation process

---

## 8) Small-File Maintenance: Scheduled vs Real-Time

Choice:
- Scheduled maintenance (daily via Airflow)

Rationale:
- Batch compaction more efficient
- Predictable resource usage
- Aligns with snapshot expiration schedule

Cost:
- Files may accumulate between runs
- Slight delay in optimization

Mitigation:
- Daily schedule ensures timely compaction
- Configurable retention policies
- Monitor file count metrics

---

## 9) Reverse ETL: Postgres vs Kafka (Project 2)

Choice:
- Both supported (dual write pattern)

Postgres upsert:
- Strong consistency
- Transactional guarantees
- Suitable for CRM/operational systems

Kafka events:
- Eventual consistency
- Scalable, decoupled
- Suitable for real-time activation

Rationale:
- Different use cases require different semantics
- Dual write provides flexibility

Cost:
- Need to handle partial failures
- Consistency between systems

Mitigation:
- Idempotent writes (upsert with run_id)
- Retry logic with backoff
- Monitoring for success rates

---

## 10) Quality Gate Placement: dbt Tests + Airflow Gate

Choice:
- dbt tests (data quality checks)
- Airflow quality_gate_cdc DAG (enforcement)

Rationale:
- dbt tests: declarative, version-controlled
- Airflow gate: enforces before downstream publishing
- Separation of concerns (checks vs enforcement)

Cost:
- Two systems to maintain
- Need to sync test definitions

Mitigation:
- dbt tests stored in schema.yml
- Airflow DAG runs dbt test, checks results
- Failure blocks downstream (API/Reverse ETL)
- Alerting on failures
