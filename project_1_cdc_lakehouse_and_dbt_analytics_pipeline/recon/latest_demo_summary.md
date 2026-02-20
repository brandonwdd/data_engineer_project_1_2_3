# Latest Demo Summary

Date: 2026-01-16  
Demo Scope: Failure Recovery + Kafka Replay + Idempotency Validation

## Scenarios Executed

1) Spark Streaming Failure Recovery  
- Killed Bronze ingestion job during active processing  
- Restarted job using the same checkpoint location  
- Verified:
  - No gaps in Bronze CDC event_uids  
  - Stable Silver entity row counts  
  - No data loss

2) Kafka Replay & Idempotency  
- Reset consumer group offsets for a bounded CDC window  
- Replayed events into Bronze  
- Re-ran Silver merge job  
- Verified:
  - No duplicate entity keys in Silver  
  - Gold KPI checksums unchanged across 3 runs  

3) Deterministic Reprocessing  
- Reprocessed Silver and Gold from Bronze  
- Compared outputs with previous snapshots  
- Verified:
  - KPI metrics identical  
  - No ordering drift

## Evidence Artifacts

- recon/2026-01-15_demo1_bronze_silver_counts.csv  
- recon/2026-01-15_demo1_gold_kpi_checksum.txt  
- recon/2026-01-16_demo2_replay_comparison.csv  

## Final Result

All scenarios PASSED.  
The CDC Lakehouse pipeline demonstrated:
- Replayability  
- Deterministic idempotent behavior  
- Production-grade failure recovery guarantees
