# Governance Architecture

## Overview

Project 3 provides a governance layer for Project 1 and Project 2, ensuring data quality and release safety.

## Architecture Flow

```
Code change (PR)
    ↓
GitHub Actions CI
    ├─ Lint (Python/SQL)
    ├─ Contract validation
    ├─ Unit tests
    └─ dbt Compile/Test
    ↓
Quality gate (Airflow)
    ├─ Contract validation
    ├─ dbt tests (Project 1 + 2)
    ├─ Custom quality checks
    └─ Completeness checks
    ↓
Release decision
    ├─ All gates pass → release allowed
    └─ Any gate fails → release blocked
```

## Core Components

### 1. Data Contracts

**Location**: `contracts/`

**Features**:
- Define CDC event contracts (`contracts/cdc/`)
- Define Metrics contracts (`contracts/metrics/`)
- Schema evolution policy
- PII annotation rules

**Validator**: `tools/contract_validator/contract_validator.py`

**Validation rules**:
- Required fields
- op semantics
- Payload rules
- Schema field checks
- Schema evolution policy checks

### 2. Quality Gates

**Location**: `orchestration/airflow/dags/quality_gate_enforcement.py`

**Gate types**:

1. **Contract validation**
   - Validate all contract file structures
   - Validate CDC events against contracts

2. **dbt tests**
   - Project 1 dbt tests
   - Project 2 dbt tests
   - Any failure → block release

3. **Custom quality checks**
   - Referential integrity (payments.order_id must exist in orders)
   - Amount consistency (captured_amount <= total_gmv)
   - Non-negative amount checks

4. **Completeness checks**
   - Expected partitions exist
   - Missing partition → block release

**Blocking mechanism**:
- Airflow DAG failure → downstream tasks skipped
- Release process blocked
- Alerts triggered

### 3. CI/CD (GitHub Actions)

**Location**: `.github/workflows/ci.yml`

**Workflow**:

1. **Lint**
   - Python: flake8, black, isort
   - SQL: syntax check

2. **Contract validation**
   - Validate all contract files
   - Output validation results

3. **Unit tests**
   - Project 1 unit tests
   - Project 3 contract validator tests
   - Coverage report

4. **dbt Compile/Test**
   - Project 1 dbt compile
   - Project 2 dbt compile
   - SQL syntax validation

**Blocking mechanism**:
- All checks must pass before PR merge
- Failure → PR cannot merge

## Integration Points

### With Project 1

- **Contract validation**: Validate Project 1 CDC events
- **dbt tests**: Run Project 1 dbt tests
- **Quality checks**: Check Project 1 data quality

### With Project 2

- **Contract validation**: Validate Project 2 Metrics contracts
- **dbt tests**: Run Project 2 dbt tests
- **Quality checks**: Check Project 2 data quality

### With Airflow

- **Quality gate DAG**: Runs hourly
- **Blocking mechanism**: Blocks downstream release on failure
- **Alerts**: Triggers alerts on failure

## Data Flow

### Normal Flow

```
1. Developer submits PR
   ↓
2. GitHub Actions CI runs
   ├─ Lint ✅
   ├─ Contract validation ✅
   ├─ Unit tests ✅
   └─ dbt Compile ✅
   ↓
3. PR merged
   ↓
4. Airflow quality gate runs
   ├─ Contract validation ✅
   ├─ dbt tests ✅
   ├─ Custom checks ✅
   └─ Completeness ✅
   ↓
5. All gates pass → release allowed
```

### Blocked Flow

```
1. Developer submits PR
   ↓
2. GitHub Actions CI runs
   └─ Contract validation ❌ (fails)
   ↓
3. PR cannot merge (blocked)
   ↓
4. Developer fixes issue
   ↓
5. Re-submit PR
```

Or

```
1. Airflow quality gate runs
   └─ dbt tests ❌ (fails)
   ↓
2. DAG fails → release blocked
   ↓
3. Alert triggered
   ↓
4. Fix issue and re-run
```

## Contract Definitions

### CDC Contract Structure

```yaml
version: v1
domain: project_1
entity: orders
primary_key: [order_id]
required_envelope_fields: [op, ts_ms, source]
op_semantics:
  allowed_ops: ["c", "u", "d", "r"]
schema:
  fields:
    order_id:
      type: int64
      nullable: false
schema_evolution_policy:
  add_column:
    allowed: true
    rule: "new fields must be nullable"
  drop_column:
    allowed: false
    rule: "use deprecation window"
```

### Metrics Contract Structure

```yaml
version: v1
domain: project_2
entity: kpis
primary_key: [kpi_date, metric_version]
required_fields: [kpi_date, total_gmv]
schema:
  fields:
    total_gmv:
      type: decimal(18,2)
      nullable: false
      constraints: [">= 0"]
```

## Quality Check Types

### 1. Schema Tests (dbt)

- `not_null`: Field not null
- `unique`: Field unique
- `relationships`: Referential integrity
- `accepted_values`: Enum values

### 2. Custom SQL Checks

- Referential integrity
- Amount consistency
- Non-negative amounts
- State machine validity

### 3. Completeness Checks

- Partition completeness
- Data range checks
- Missing partition detection

## Alerts and Monitoring

### Alert Rules

- Contract validation fails → immediate alert
- dbt tests fail → immediate alert
- Quality gate fails → immediate alert
- Completeness fails → immediate alert

### Monitoring Metrics

- Contract validation pass rate
- dbt tests pass rate
- Quality gate pass rate
- Release block count
- CI pipeline success rate

## Best Practices

1. **Contracts first**: Define contracts before changes
2. **Evolution policy**: Schema changes must follow evolution policy
3. **Test coverage**: Critical logic must have tests
4. **Strict gates**: Any failure blocks release
5. **Traceability**: All validation results traceable
