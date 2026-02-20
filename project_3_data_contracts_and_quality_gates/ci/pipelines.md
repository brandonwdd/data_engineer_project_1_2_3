# CI Pipelines

Pipelines:
- contract_validation
- dbt_tests
- quality_gates
- release_blocking

All pipelines must pass before merge.

NOTE: Canonical CI entrypoint is .github/workflows/ci.yml. Files under ci/github_actions are legacy/reference examples.
