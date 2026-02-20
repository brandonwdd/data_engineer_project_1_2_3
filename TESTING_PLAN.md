# Testing Plan: Project 1 + Project 2 End-to-End

## 📋 Overview

This plan covers end-to-end validation of Project 1 (CDC Lakehouse) and Project 2 (Metrics Service + Reverse ETL).

---

## 🎯 Objectives

1. **Validate Project 1 data pipeline**
   - CDC capture → Bronze → Silver → Gold
   - Idempotency, replay, data correctness

2. **Validate Project 2 metrics service**
   - dbt semantic layer → Metrics API → Reverse ETL
   - Quality gates, versioning, idempotency

3. **Validate end-to-end integration**
   - Project 1 Gold → Project 2 → downstream systems
   - Data consistency, service availability

---

## 📊 Test Matrix

| Category | Project 1 | Project 2 | Integration |
|----------|-----------|-----------|-------------|
| Unit tests | ✅ | ✅ | - |
| Integration | ✅ | ✅ | ✅ |
| End-to-end | ✅ | ✅ | ✅ |
| Performance | ✅ | ✅ | ✅ |
| Failure recovery | ✅ | - | - |
| Idempotency | ✅ | ✅ | - |

---

## 🧪 Phases

### Phase 1: Project 1 Base Tests

#### 1.1 Infra validation

```bash
# Check Docker services
cd project_1/platform/local
docker compose ps

# Verify:
# - Postgres (postgres)
# - Kafka (kafka)
# - Kafka Connect (kafka-connect)
# - MinIO (minio)
```

**Acceptance**:
- ✅ All services up
- ✅ Postgres wal_level=logical
- ✅ Kafka topics created

#### 1.2 CDC capture

```bash
# Create Debezium connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @project_1/connectors/debezium/configs/project_1_connector.json

# Insert test data
docker exec -it postgres psql -U postgres -d project1 -c "
INSERT INTO public.users(user_id, email, status, created_at, updated_at)
VALUES (1, 'test@example.com', 'active', now(), now());
"

# Verify CDC events
docker exec -it kafka sh -lc \
  "kafka-console-consumer --bootstrap-server localhost:9092 \
   --topic dbserver_docker.public.users --from-beginning --max-messages 1"
```

**Acceptance**:
- ✅ Debezium connector RUNNING
- ✅ CDC events on Kafka topic
- ✅ Debezium envelope format

#### 1.3 Bronze layer

```bash
# Start Bronze ingest
cd project_1
make bronze-run

# Verify writes (Trino)
trino --server localhost:8080 --execute "
SELECT COUNT(*) FROM iceberg.bronze.raw_cdc;
"
```

**Acceptance**:
- ✅ Bronze table has data
- ✅ event_uid unique
- ✅ ordering_key correct

#### 1.4 Silver layer

```bash
# Run Silver merge
cd project_1
make silver-run

# Verify
trino --server localhost:8080 --execute "
SELECT COUNT(*) FROM iceberg.silver.users;
SELECT COUNT(*) FROM iceberg.silver.orders;
SELECT COUNT(*) FROM iceberg.silver.payments;
"
```

**Acceptance**:
- ✅ Silver tables have data
- ✅ PK unique
- ✅ Deletes handled

#### 1.5 Gold layer

```bash
# Run dbt
cd project_1/analytics/dbt
dbt run
dbt test

# Verify Gold
trino --server localhost:8080 --execute "
SELECT * FROM iceberg.mart.mart_kpis_daily LIMIT 10;
"
```

**Acceptance**:
- ✅ dbt run succeeds
- ✅ dbt tests pass
- ✅ Gold has data

#### 1.6 Demo scripts

```bash
# Demo 1: Failure recovery
./project_1_cdc_lakehouse_and_dbt_analytics_pipeline/scripts/demo_failure_recovery.sh

# Demo 2: Replay idempotency
./project_1_cdc_lakehouse_and_dbt_analytics_pipeline/scripts/demo_replay_idempotency.sh

# Demo 3: Schema evolution
./project_1_cdc_lakehouse_and_dbt_analytics_pipeline/scripts/demo_schema_evolution.sh
```

**Acceptance**:
- ✅ All demos succeed
- ✅ Reconciliation reports generated
- ✅ Idempotency verified

---

### Phase 2: Project 2 Base Tests

#### 2.1 dbt semantic layer

```bash
# Run Project 2 dbt
cd project_2_metrics_api_and_reverse_etl_metrics_api_and_reverse_etl/analytics/dbt
dbt deps
dbt run
dbt test

# Verify models
trino --server localhost:8080 --execute "
SELECT * FROM iceberg.mart.mart_kpis_daily_v1 LIMIT 10;
SELECT * FROM iceberg.mart.mart_user_segments LIMIT 10;
"
```

**Acceptance**:
- ✅ dbt run/test succeed
- ✅ Correct refs to Project 1 Gold
- ✅ User segments correct
- ✅ dbt tests pass

#### 2.2 Metrics API

```bash
# Start API
cd project_2_metrics_api_and_reverse_etl
make api-start

# Test endpoints
curl http://localhost:8000/health
curl "http://localhost:8000/kpi?date=$(date +%Y-%m-%d)&version=v1"
curl "http://localhost:8000/user_segment?segment=high_value&version=v1"
curl http://localhost:8000/versions
```

**Acceptance**:
- ✅ Health check OK
- ✅ KPI returns data
- ✅ User segment returns data
- ✅ Versions OK

#### 2.3 Reverse ETL

```bash
# Postgres upsert
cd project_2_metrics_api_and_reverse_etl
make reverse-etl-postgres

# Verify
psql -h localhost -U postgres -d project1 -c "
SELECT COUNT(*) FROM customer_segments;
"

# Kafka publish (Kafka must be running)
make reverse-etl-kafka

# Verify messages
kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic segment_updates --from-beginning --max-messages 10
```

**Acceptance**:
- ✅ Postgres upsert OK
- ✅ customer_segments populated
- ✅ Kafka publish OK
- ✅ Idempotent (re-runs safe)

#### 2.4 Quality gates

```bash
# Run Airflow DAG or manual flow
cd project_2_metrics_api_and_reverse_etl
./scripts/demo_metric_release.sh
```

**Acceptance**:
- ✅ dbt tests pass
- ✅ Completeness checks pass
- ✅ Release log written

---

### Phase 3: End-to-End Integration

#### 3.1 Full data flow

```bash
# 1. Project 1: Generate data
cd project_1
# Insert test data into Postgres
# Run Bronze → Silver → Gold

# 2. Project 2: Consume
cd project_2_metrics_api_and_reverse_etl
dbt run
make api-start

# 3. Verify E2E
curl "http://localhost:8000/kpi?date=$(date +%Y-%m-%d)&version=v1"
```

**Acceptance**:
- ✅ Project 1 produces correct data
- ✅ Project 2 reads Project 1 Gold
- ✅ API returns correct KPIs

#### 3.2 Data consistency

```bash
# Compare KPIs: Project 1 vs Project 2
# Project 1
trino --server localhost:8080 --execute "
SELECT 
    kpi_date,
    total_gmv,
    order_count
FROM iceberg.mart.mart_kpis_daily
WHERE kpi_date = CURRENT_DATE;
"

# Project 2
trino --server localhost:8080 --execute "
SELECT 
    kpi_date,
    total_gmv,
    order_count
FROM iceberg.mart.mart_kpis_daily_v1
WHERE kpi_date = CURRENT_DATE;
"
```

**Acceptance**:
- ✅ KPIs match between projects
- ✅ Differences within acceptable range (if any)

#### 3.3 Reverse ETL loop

```bash
# 1. Project 2 produces segments
cd project_2_metrics_api_and_reverse_etl
dbt run --select mart_user_segments

# 2. Run Reverse ETL
make reverse-etl-postgres
make reverse-etl-kafka

# 3. Verify write-back
psql -h localhost -U postgres -d project1 -c "
SELECT 
    value_segment,
    COUNT(*) as user_count
FROM customer_segments
GROUP BY value_segment;
"
```

**Acceptance**:
- ✅ Segments produced
- ✅ Postgres write-back OK
- ✅ Kafka publish OK
- ✅ Data usable by downstream

---

### Phase 4: Performance

#### 4.1 API performance

```bash
cd project_2_metrics_api_and_reverse_etl
./scripts/demo_api_latency.sh
```

**Acceptance**:
- ✅ API p95 < 300ms
- ✅ Success rate > 99%

#### 4.2 Data freshness

```bash
# Check KPI freshness
trino --server localhost:8080 --execute "
SELECT 
    MAX(_computed_at) as latest_compute,
    CURRENT_TIMESTAMP as now,
    TIMESTAMP_DIFF('MINUTE', MAX(_computed_at), CURRENT_TIMESTAMP) as freshness_minutes
FROM iceberg.mart.mart_kpis_daily_v1;
"
```

**Acceptance**:
- ✅ KPI freshness < 10 minutes

---

### Phase 5: Failure recovery

#### 5.1 Project 1 recovery

```bash
cd project_1
./scripts/demo_failure_recovery.sh
```

**Acceptance**:
- ✅ Checkpoint recovery OK
- ✅ No data loss
- ✅ Reconciliation passes

#### 5.2 Project 2 API recovery

```bash
# 1. Start API
cd project_2_metrics_api_and_reverse_etl
make api-start

# 2. Simulate failure (kill process)
# 3. Restart
make api-start

# 4. Verify
curl http://localhost:8000/health
```

**Acceptance**:
- ✅ API restarts cleanly
- ✅ Health and endpoints OK after restart

---

## 📝 Checklists

### Project 1

- [ ] Infra services up
- [ ] Debezium connector created
- [ ] CDC events captured
- [ ] Bronze writes OK
- [ ] Silver merge OK
- [ ] Gold dbt run/test OK
- [ ] Demo scripts OK
- [ ] Failure recovery OK
- [ ] Idempotency OK

### Project 2

- [ ] dbt semantic layer OK
- [ ] Project 1 Gold refs OK
- [ ] Metrics API up
- [ ] API endpoints OK
- [ ] Reverse ETL Postgres OK
- [ ] Reverse ETL Kafka OK
- [ ] Quality gate flow OK
- [ ] Release log OK
- [ ] Idempotency OK

### Integration

- [ ] E2E data flow OK
- [ ] Data consistency OK
- [ ] Reverse ETL loop OK
- [ ] API performance meets SLO
- [ ] Data freshness meets SLO

---

## 🚀 Quick commands

### One-command scripts (TBD)

```bash
# Project 1
./test_project1.sh

# Project 2
./test_project2.sh

# E2E
./test_e2e.sh
```

---

## 📊 Test report template

After testing, produce a report:

```
Test date: YYYY-MM-DD
Tester: [Name]

Project 1:
- Infra: ✅/❌
- CDC: ✅/❌
- Bronze: ✅/❌
- Silver: ✅/❌
- Gold: ✅/❌
- Demos: ✅/❌

Project 2:
- dbt: ✅/❌
- Metrics API: ✅/❌
- Reverse ETL: ✅/❌
- Quality gates: ✅/❌

Integration:
- E2E flow: ✅/❌
- Data consistency: ✅/❌
- Performance: ✅/❌

Issues:
1. [Description]
2. [Description]

Summary:
[Summary]
```

---

## 🔧 Troubleshooting

### Common issues

1. **Trino connection fails**
   - Verify Trino is running
   - Check port and network

2. **dbt model failures**
   - Verify Project 1 Gold tables exist
   - Check Trino config and dbt logs

3. **API query failures**
   - Check Trino connection and tables
   - Verify data has been generated

4. **Reverse ETL failures**
   - Check Postgres/Kafka connectivity
   - Verify tables/topics exist and check logs

---

## 📚 References

- [Project 1 README](project_1/README.md)
- [Project 2 README](project_2_metrics_api_and_reverse_etl/README.md)
- [Project 1 Runbook](project_1/runbook/)
- [Project 2 Runbook](project_2_metrics_api_and_reverse_etl/runbook/)

---

## ✅ Done criteria

All of the following must pass:

1. ✅ Project 1 tests pass
2. ✅ Project 2 tests pass
3. ✅ E2E integration pass
4. ✅ Performance meets SLO
5. ✅ Failure recovery verified
6. ✅ All demo scripts pass
7. ✅ Test report generated
