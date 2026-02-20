# Key Architecture Trade-offs (Project 2)

This document records the main design decisions for Project 2.

---

## 1) Fully Based on Project 1 vs Standalone Data Pipeline

**Choice**: Fully based on Project 1, direct reference to Gold tables

**Rationale**:
- Single source of truth (no duplicate data)
- Unified metric definitions (all KPIs from same mart)
- Lower maintenance cost
- Matches production pattern (Metrics Service consumes Lakehouse)

**Cost**:
- Depends on Project 1 data quality
- Project 1 changes affect Project 2

**Mitigation**:
- Project 1 quality gates ensure data quality
- Project 2 has its own quality gates (secondary validation)
- Versioning allows switching versions

---

## 2) dbt Semantic Layer vs Direct Query

**Choice**: Lightweight dbt semantic layer (stg/int/mart)

**Rationale**:
- Consistent semantic layer
- Supports business logic (user segmentation)
- Easy versioning (mart_kpis_daily_v1)
- Easier testing and quality checks

**Cost**:
- Extra abstraction layer
- dbt models to maintain

**Mitigation**:
- stg directly references (no transform)
- int only for necessary business logic
- mart kept minimal (versioning only)

---

## 3) Metric Versioning Strategy

**Choice**: Table-level versioning (mart_kpis_daily_v1)

**Rationale**:
- Simple and clear
- API routes via version parameter
- Multiple versions can coexist

**Cost**:
- Multiple tables to maintain
- Higher storage cost

**Mitigation**:
- Keep old versions 1–2 cycles then drop
- Release log tracks version lifecycle

---

## 4) Reverse ETL: Postgres vs Kafka

**Choice**: Both (dual write)

**Rationale**:
- Postgres: strong consistency, suits CRM/operational systems
- Kafka: eventual consistency, suits real-time activation
- Different use cases need different semantics

**Cost**:
- Partial failures must be handled
- Consistency between both systems

**Mitigation**:
- Postgres: upsert with ON CONFLICT (idempotent)
- Kafka: keyed by user_id (ordering)
- Retry logic and monitoring

---

## 5) Quality Gate Placement

**Choice**: dbt tests + Airflow gate

**Rationale**:
- dbt tests: declarative, version-controlled
- Airflow gate: blocks at runtime
- Separation of concerns (checks vs enforcement)

**Cost**:
- Two systems to maintain
- Test definitions must stay in sync

**Mitigation**:
- dbt tests in schema.yml
- Airflow DAG runs dbt test
- Failure blocks downstream release

---

## 6) API Caching Strategy

**Choice**: TTL cache (future implementation)

**Rationale**:
- Date-scoped KPI queries suit caching
- Reduces Trino load
- Improves response time

**Cost**:
- Cache consistency on data updates
- Memory/storage cost

**Mitigation**:
- TTL 5–10 minutes
- Cache key includes date and version
- Invalidate on data updates

---

## 7) Release Log Granularity

**Choice**: One log entry per release

**Rationale**:
- Traceable releases
- Version comparison
- Easier auditing

**Cost**:
- Table growth
- Query performance

**Mitigation**:
- Partition by metric_version
- Archive old release logs periodically

---

## 8) User Segmentation Compute Location

**Choice**: dbt int layer

**Rationale**:
- Leverages SQL
- Version control and tests
- Easier to maintain

**Cost**:
- Computation at query time
- May affect performance

**Mitigation**:
- Materialize to mart
- Periodic refresh (not real-time)

---

## 9) API Query Timeout Strategy

**Choice**: 30-second timeout

**Rationale**:
- Balance UX and system stability
- Avoid long-running queries blocking

**Cost**:
- Complex queries may timeout
- Query optimization needed

**Mitigation**:
- Optimize queries (indexes)
- Limit result size
- Monitor timeout rate

---

## 10) Quality Gate Blocking Granularity

**Choice**: Any failure blocks release

**Rationale**:
- Ensures data quality
- Prevents bad data affecting business
- Production-grade standard

**Cost**:
- May reduce release frequency
- Requires fast fixes

**Mitigation**:
- Clear error messages
- Fast fix process
- Alerting
