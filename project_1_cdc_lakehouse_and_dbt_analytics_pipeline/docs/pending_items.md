# Project 1 Pending Items

## ~~Optional Components~~  **Completed**

### 1. ~~Terraform IaC~~  **Completed**

**Status**:  Implemented

**Contents**:
-  AWS S3 bucket creation (production object storage)
-  IAM roles/policies (S3 access permissions)
-  MinIO/S3 switching support (dev env optional)
-  Switch scripts (switch_to_s3.sh, switch_to_minio.sh)

**Files**:
- `infra/terraform/environments/prod/` — Production (S3 + IAM)
- `infra/terraform/environments/dev/` — Dev (optional S3 or MinIO)
- `infra/terraform/environments/local/` — Local (MinIO)

**Usage**: See `infra/terraform/README.md` and `docs/quick_start_terraform_ci.md`

---

### 2. ~~GitHub Actions CI/CD~~  **Completed**

**Status**:  Implemented

**Contents**:
-  PR trigger: lint (Python black/flake8, SQL dbt parse)
-  Unit tests: `pytest streaming/spark/tests` + coverage
-  dbt compile + test (schema tests)
-  Terraform validate (all environments)
-  Test reports and artifacts

**Files**:
- `.github/workflows/ci.yml` — CI workflow
- `.github/README.md` — CI/CD docs

**Usage**: Auto-runs (PR/Push), or see `.github/README.md` for local run

---

##  One Item to Verify (Evidence #3: Idempotency Acceptance)

### Issue: Idempotency acceptance needs runtime verification

**Status**: Code implemented, but needs actual test run

**Requirement**:
> "Same window run N times, Gold KPI checksum unchanged"
> Write N=3 or 5 in README, and script automatically runs 3 times.

**Current implementation**:
-  Silver merge logic implements idempotency (ordering_key comparison)
-  `demo_replay_idempotency.sh` script created
-  **But hasn't been run yet**, cannot prove checksum really unchanged

**What to do**:

1. **Run Demo-2 script**:
   ```bash
   ./scripts/demo_replay_idempotency.sh
   ```

2. **Verification steps**:
   - Generate test data window
   - Record initial KPI checksum (Run 1)
   - Reset Kafka offsets, re-run Bronze + Silver
   - Record final KPI checksum (Run 2)
   - **Verify Run 1 and Run 2 checksums match exactly**

3. **If checksum mismatch**:
   - Check Silver merge logic (is ordering_key comparison correct)
   - Check if dbt models have non-deterministic functions
   - Fix issues, re-verify

4. **If checksum matches**:
   -  Evidence #3 complete
   - Update README, state verified N=3 times, checksum unchanged
   - Save verification report to `recon/demo2_idempotency_validation_YYYY-MM-DD.txt`

**Why important**:
- Common interview question: "How do you prove idempotency?"
- Must have **actual runtime results** as evidence
- Code implementation ≠ actual verification

---

##  Summary

###  Completed (Code 100%)
1.  **Terraform IaC** — S3 bucket + IAM, supports MinIO/S3 switching
2.  **GitHub Actions CI/CD** — Lint, tests, dbt, terraform validate

###  Pending Verification (Runtime Testing)
- **Idempotency acceptance** (Evidence #3) — Must actually run `demo_replay_idempotency.sh` and verify checksum unchanged

---

##  Next Steps (Test Verification)

### Must Complete (Evidence Verification)

1. **Run idempotency validation** (Evidence #3)
   - Run `demo_replay_idempotency.sh` at least 3 times
   - Verify Gold KPI checksum unchanged after each run
   - Generate verification report
   - **Time**: 1-2 hours
   - **Value**: Core evidence, interview must-ask

### Optional Tests (Recommended)

2. **Run other demo scripts**
   - `demo_failure_recovery.sh` — verify failure recovery
   - `demo_schema_evolution.sh` — verify schema evolution

3. **End-to-end flow test**
   - Bronze → Silver → Gold full flow
   - Verify data correctness

---

##  Completion Criteria

### Evidence #3 Completion Criteria:
- [ ] Run `demo_replay_idempotency.sh` at least 3 times
- [ ] After each run, Gold KPI checksum exactly matches
- [ ] Generate verification report (includes Run 1, Run 2, Run 3 checksum comparison)
- [ ] Update README, state idempotency verified (N=3)

### Project Completion Criteria:
-  All code implemented
-  Terraform IaC completed
-  CI/CD completed
-  Runtime test verification (idempotency, demo scripts)
