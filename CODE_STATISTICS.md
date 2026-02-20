# Three-Project Code Line Count Report

## 📊 Overview

| Project | Lines | Share |
|---------|-------|-------|
| **Project 1** | 3,650 | 52.0% |
| **Project 2** | 2,144 | 30.5% |
| **Project 3** | 1,225 | 17.5% |
| **Total** | **7,019** | 100% |

---

## 📁 By Project

### Project 1: Real-time CDC Lakehouse

| Type | Lines | Share |
|------|-------|-------|
| Python | 1,256 | 34.4% |
| SQL | 287 | 7.9% |
| YAML | 898 | 24.6% |
| Shell | 731 | 20.0% |
| JSON/Terraform | 478 | 13.1% |
| **Total** | **3,650** | 100% |

**Main components**:
- Spark Streaming (Bronze/Silver)
- dbt models (stg/int/mart)
- Airflow DAGs
- K8s deploy config
- Terraform infra

---

### Project 2: Metrics Service + Reverse ETL

| Type | Lines | Share |
|------|-------|-------|
| Python | 1,036 | 48.3% |
| SQL | 158 | 7.4% |
| YAML | 378 | 17.6% |
| Shell | 572 | 26.7% |
| **Total** | **2,144** | 100% |

**Main components**:
- FastAPI service
- Reverse ETL (Postgres + Kafka)
- dbt models (references Project 1)
- Airflow DAGs
- K8s deploy config

---

### Project 3: Data Contracts + Quality Gates + CI

| Type | Lines | Share |
|------|-------|-------|
| Python | 563 | 46.0% |
| SQL | 0 | 0% |
| YAML | 317 | 25.9% |
| Shell | 345 | 28.1% |
| **Total** | **1,225** | 100% |

**Main components**:
- Contract validator (Python)
- Quality gate Airflow DAG
- GitHub Actions CI
- Contract definitions (YAML)

---

## 📈 By File Type

| Type | Project 1 | Project 2 | Project 3 | Total |
|------|-----------|-----------|-----------|-------|
| **Python** | 1,256 | 1,036 | 563 | **2,855** |
| **SQL** | 287 | 158 | 0 | **445** |
| **YAML** | 898 | 378 | 317 | **1,593** |
| **Shell** | 731 | 572 | 345 | **1,648** |
| **Other** | 478 | 0 | 0 | **478** |
| **Total** | **3,650** | **2,144** | **1,225** | **7,019** |

---

## 🎯 Distribution

### Python (2,855 lines, 40.7%)

- **Project 1**: Spark Streaming, parsing, merge logic
- **Project 2**: FastAPI, Reverse ETL, business logic
- **Project 3**: Contract validator, quality checks

### SQL (445 lines, 6.3%)

- **Project 1**: dbt models (stg/int/mart), DDL
- **Project 2**: dbt models (references Project 1)

### YAML (1,593 lines, 22.7%)

- **Project 1**: K8s, Airflow, Datadog, contracts
- **Project 2**: K8s, Airflow, contracts
- **Project 3**: CI, contracts, quality gate config

### Shell (1,648 lines, 23.5%)

- **Project 1**: Demo, test, deploy scripts
- **Project 2**: Demo, deploy scripts
- **Project 3**: Demo, validation scripts

---

## 📝 Notes

**Scope**:
- ✅ Included: Python, SQL, YAML, Shell, JSON, Terraform
- ❌ Excluded: docs (docs/, README.md), evidence/, caches (__pycache__, .pytest_cache)

**Method**:
- PowerShell `Get-Content | Measure-Object -Line`
- All lines counted (including blanks and comments)

---

## 🎉 Summary

Total **7,019 lines** across three projects:

- **Project 1** (3,650): Most complex; full data pipeline
- **Project 2** (2,144): Medium; metrics service and write-back
- **Project 3** (1,225): Lightest; governance layer

Quality:
- ✅ Clear structure (layered architecture)
- ✅ Good docs (README, architecture, SLO, runbooks)
- ✅ Tests (unit tests, demo scripts)
- ✅ Production-style (K8s, monitoring, quality gates)

---

**Generated**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
