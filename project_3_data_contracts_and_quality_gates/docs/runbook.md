# Governance Runbook

## Overview

This runbook provides operational guidance for Project 3 governance layer.

---

## Common Scenarios

### Scenario 1: Contract Validation Failure

**Symptom**: Contract validation fails in CI or Airflow

**Diagnosis**:
```bash
# Manual validation
cd project_3_data_contracts_and_quality_gates/tools/contract_validator
python contract_validator.py --contracts-dir ../../contracts
```

**Steps**:
1. Check failure details (which contract, which field)
2. Check contract file syntax
3. Fix contract definition
4. Re-run validation

**Common causes**:
- YAML syntax errors
- Missing required fields
- Incomplete schema definition

---

### Scenario 2: dbt Tests Failure

**Symptom**: dbt tests fail in quality gate

**Diagnosis**:
```bash
# Project 1
cd project_1_cdc_lakehouse_and_dbt_analytics_pipeline/analytics/dbt
dbt test --profiles-dir . --project-dir . --store-failures

# Project 2
cd project_2_metrics_api_and_reverse_etl/analytics/dbt
dbt test --profiles-dir . --project-dir . --store-failures
```

**Steps**:
1. Check failed test name
2. Check test failure details (`target/` directory)
3. Fix data issues or adjust test logic
4. Re-run dbt test

**Common causes**:
- Data quality (nulls, duplicates)
- Referential integrity violations
- Enum value mismatches

---

### Scenario 3: Custom Quality Check Failure

**Symptom**: Custom checks fail in quality gate

**Diagnosis**:
```bash
# Manual check
trino --server localhost:8080 --execute "
SELECT COUNT(*) 
FROM iceberg.mart.fct_payments p
LEFT JOIN iceberg.mart.fct_orders o ON p.order_id = o.order_id
WHERE o.order_id IS NULL;
"
```

**Steps**:
1. Check which specific check failed
2. Manually run SQL check
3. Fix data issues
4. Re-run quality gate

**Common causes**:
- Referential integrity violations
- Amount consistency violations
- Non-negative constraint violations

---

### Scenario 4: Completeness Check Failure

**Symptom**: Completeness check fails in quality gate

**Diagnosis**:
```bash
trino --server localhost:8080 --execute "
SELECT 
    COUNT(DISTINCT kpi_date) AS partition_count,
    MIN(kpi_date) AS min_date,
    MAX(kpi_date) AS max_date
FROM iceberg.mart.mart_kpis_daily
WHERE kpi_date >= CURRENT_DATE - INTERVAL '7' DAY;
"
```

**Steps**:
1. Identify missing partition dates
2. Check Project 1 data pipeline status
3. Manually backfill missing partitions (if needed)
4. Re-run quality gate

**Common causes**:
- Project 1 Spark job failures
- Data source issues
- Timezone issues

---

### Scenario 5: CI Pipeline Failure

**Symptom**: GitHub Actions CI fails

**Diagnosis**:
- Check GitHub Actions logs
- Check failed step (lint, test, compile)

**Steps**:
1. Check failure details
2. Reproduce locally
3. Fix code issues
4. Re-submit PR

**Common causes**:
- Code format issues (black/isort)
- Syntax errors
- Test failures

---

## Release Block Handling

### When Release Is Blocked

Release blocked when:
1. Contract validation fails
2. dbt tests fail
3. Custom quality checks fail
4. Completeness check fails
5. CI pipeline fails (PR cannot merge)

### Process

1. **Identify issue**: Check failure logs
2. **Root cause**: Analyze failure reason
3. **Fix**:
   - Fix data issues
   - Fix code issues
   - Adjust test logic
4. **Verify fix**: Re-run checks
5. **Unblock**: Release continues after checks pass

---

## Contract Management

### Add New Contract

1. Create contract YAML file
2. Define schema, constraints, evolution policy
3. Run contract validator
4. Commit to version control

### Modify Existing Contract

1. Check schema evolution policy
2. Ensure backward compatibility (new fields nullable)
3. Run contract validator
4. Update related docs

### Schema Evolution Process

1. **Add field**:
   - Field must be nullable or have default
   - Update contract definition
   - Verify backward compatibility

2. **Delete field**:
   - Mark as deprecated first
   - Wait 1–2 version cycles
   - Then delete

3. **Type change**:
   - Not allowed directly
   - Introduce new field, deprecate old field

---

## Quality Gate Configuration

### Add New Check

1. Add new task in Airflow DAG
2. Implement check logic
3. Throw exception on failure (block release)
4. Update docs

### Adjust Check Thresholds

1. Modify thresholds in check logic
2. Test new thresholds
3. Update docs
4. Deploy to Airflow

---

## Monitoring and Alerts

### Key Metrics

- Contract validation pass rate
- dbt tests pass rate
- Quality gate pass rate
- CI pipeline success rate
- Release block count

### Alert Rules

- Contract validation fails → immediate alert
- dbt tests fail → immediate alert
- Quality gate fails → immediate alert
- CI pipeline fails → alert

### View History

```bash
# View Airflow DAG run history
airflow dags list-runs -d quality_gate_enforcement

# View GitHub Actions history
# Check Actions tab in GitHub UI
```

---

## Best Practices

1. **Contracts first**: Define contracts before changes
2. **Test coverage**: Critical logic must have tests
3. **Strict gates**: Any failure blocks release
4. **Fast response**: Fix quickly after block
5. **Update docs**: Update docs when changes occur

---

## References

- [`docs/architecture.md`](architecture.md) — Architecture
- [`docs/slo.md`](slo.md) — SLO definitions
- [`contracts/rules.md`](../contracts/rules.md) — Contract rules
- [`quality_gates/rules.md`](../quality_gates/rules.md) — Quality gate rules
