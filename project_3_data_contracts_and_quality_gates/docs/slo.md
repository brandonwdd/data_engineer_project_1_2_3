# Service Level Objectives (SLO)

## Overview

Project 3 SLOs define service level targets for the governance layer.

---

## SLO Definitions

### 1. Contract Validation Pass Rate

**Metric**: Contract validation pass rate

**Target**: 100%

**Definition**: All contract files must be valid; all events must conform

**Measurement**:
- Contract file validation: structure integrity
- Event validation: conforms to contract rules

**Monitoring**:
- Contract validation step in CI
- Contract validation in Airflow quality gate

**Impact**:
- Data quality: invalid contracts cause data quality issues
- Business: high (prevents bad data entering system)

---

### 2. dbt Tests Pass Rate

**Metric**: dbt tests pass rate

**Target**: 100% (must pass before release)

**Definition**: All dbt tests must pass to release

**Measurement**:
- Project 1 dbt tests
- Project 2 dbt tests
- Any test failure = release blocked

**Monitoring**:
- dbt test step in CI
- dbt tests in Airflow quality gate

**Impact**:
- Data quality: test failure indicates data quality issues
- Business: high (prevents bad data release)

---

### 3. Quality Gate Pass Rate

**Metric**: Quality gate pass rate

**Target**: > 95%

**Definition**: Percentage of successful quality gate runs

**Measurement**:
- Contract validation passes
- dbt tests pass
- Custom checks pass
- Completeness passes

**Monitoring**:
- Airflow DAG success rate
- Quality gate failure count

**Impact**:
- Release efficiency: gate failures delay releases
- Business: medium (affects release speed)

---

### 4. CI Pipeline Success Rate

**Metric**: CI pipeline success rate

**Target**: > 98%

**Definition**: Percentage of PRs passing CI before merge

**Measurement**:
- Lint passes
- Contract validation passes
- Unit tests pass
- dbt compile passes

**Monitoring**:
- GitHub Actions workflow status
- PR merge block count

**Impact**:
- Development efficiency: CI failures block PR merge
- Business: medium (affects development speed)

---

### 5. Release Block Response Time

**Metric**: Time from release block to fix

**Target**: < 2 hours (P95)

**Definition**: Time from quality gate failure to fix

**Measurement**:
- Quality gate failure time
- Fix commit time
- Time difference

**Monitoring**:
- Airflow task failure time
- Fix commit time

**Impact**:
- Release speed: block time affects release frequency
- Business: medium (affects release cadence)

---

## SLO Dashboard

### Key Metrics

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| Contract validation pass rate | 100% | - | - |
| dbt tests pass rate | 100% | - | - |
| Quality gate pass rate | > 95% | - | - |
| CI pipeline success rate | > 98% | - | - |
| Release block response time | < 2h (P95) | - | - |

---

## Alert Rules

### 1. Contract Validation Failure Alert

**Condition**: Contract validation fails

**Severity**: Critical

**Notification**: Data Engineering team + On-call

**Action**: Fix contract definition or event data

---

### 2. dbt Tests Failure Alert

**Condition**: Any dbt test fails

**Severity**: Critical

**Notification**: Data Engineering team + On-call

**Action**: Fix data quality issues or adjust test logic

---

### 3. Quality Gate Failure Alert

**Condition**: Quality gate fails 2 times consecutively

**Severity**: Warning

**Notification**: Data Engineering team

**Action**: Check data quality, fix issues

---

### 4. CI Pipeline Failure Alert

**Condition**: CI pipeline fails

**Severity**: Warning

**Notification**: Developer + Data Engineering team

**Action**: Fix code issues, re-submit PR

---

## SLO Review

### Review Cycle

- **Weekly**: Check SLO achievement
- **Monthly**: Review if SLO targets are reasonable
- **Quarterly**: Evaluate if SLO adjustments needed

### Review Content

1. **SLO achievement rate**: Past week/month
2. **Alert frequency**: Alert trigger frequency and causes
3. **Improvements**: Plans for unmet SLOs
4. **Target adjustment**: Whether SLO targets need adjustment

---

## References

- [`docs/architecture.md`](architecture.md) — Architecture
- [`docs/runbook.md`](runbook.md) — Runbook
- [`quality_gates/rules.md`](../quality_gates/rules.md) — Quality gate rules
