# Postmortem: CDC Pipeline Freshness SLA Breach

Date: 2026-01-10  
Severity: SEV-2  
Duration: 17 minutes  

## Summary

The CDC Lakehouse pipeline experienced a freshness SLA breach  
where Silver tables were delayed beyond the 5-minute SLA.

## Impact

- Silver entity tables lagged by up to 17 minutes  
- Downstream Gold marts were delayed  
- BI dashboards showed stale metrics during the incident window  

## Detection

- Datadog alert: freshness_breach_silver_tables  
- Triggered when end-to-end latency exceeded SLA threshold  

## Root Cause

- Kafka partition imbalance after connector restart  
- Spark micro-batches were processing skewed partitions slowly  

## Resolution

- Rebalanced Kafka partitions  
- Restarted Spark streaming job  
- Cleared backlog and restored normal processing rate  

## Prevention

- Added Kafka partition skew monitoring  
- Introduced auto-scaling policy for Spark executors  
- Documented recovery steps in runbook.md  

## Lessons Learned

- Partition skew must be continuously monitored  
- Freshness alerts are critical for business trust  
- Runbooks reduce mean time to recovery (MTTR)
