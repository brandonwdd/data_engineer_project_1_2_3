# Contract Validator

Validates CDC and Metrics data contracts.

## Features

- Validate contract file structure
- Validate CDC events against contracts
- Validate schema evolution against policy
- Batch validate all contracts

## Usage

### Validate all contracts

```bash
python contract_validator.py --contracts-dir ../../contracts
```

### Validate single event

```bash
python contract_validator.py \
  --contract contracts/cdc/orders.yaml \
  --event test_event.json
```

### Output to file

```bash
python contract_validator.py \
  --contracts-dir ../../contracts \
  --output validation_results.json
```

## Rules

### CDC event validation

- Required fields (op, ts_ms, source)
- op semantics (allowed ops)
- Payload rules (after/before presence)
- Primary key checks
- Schema checks (nullable, allowed_values)

### Schema evolution

- Field deletion requires deprecation cycle
- Type change not allowed (introduce new field)
- New fields must be nullable or have default

## Integration

- CI/CD: GitHub Actions
- Airflow: quality gate
- Local: pre-commit hook
