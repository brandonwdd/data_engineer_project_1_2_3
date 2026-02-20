.PHONY: help validate-contracts validate-event test-quality-gates demo-contract demo-quality demo-release lint

help:
	@echo "Project 3: Data Contracts + Quality Gates + CI"
	@echo ""
	@echo "Available targets:"
	@echo "  validate-contracts    - Validate all contracts"
	@echo "  validate-event        - Validate single CDC event"
	@echo "  test-quality-gates    - Test quality gate logic"
	@echo "  demo-contract         - Run contract violation demo"
	@echo "  demo-quality          - Run quality gate failure demo"
	@echo "  demo-release          - Run release block demo"
	@echo "  lint                  - Lint Python code"

# Contract validation
validate-contracts:
	cd tools/contract_validator && \
	python contract_validator.py --contracts-dir ../../contracts

validate-event:
	@echo "Usage: make validate-event CONTRACT=contracts/cdc/orders.yaml EVENT=test_event.json"
	cd tools/contract_validator && \
	python contract_validator.py --contract $(CONTRACT) --event $(EVENT)

# Quality gates
test-quality-gates:
	@echo "Testing quality gate logic..."
	cd tools/contract_validator && \
	python contract_validator.py --contracts-dir ../../contracts

# Demo scripts
demo-contract:
	./scripts/demo_contract_violation.sh

demo-quality:
	./scripts/demo_quality_gate_failure.sh

demo-release:
	./scripts/demo_release_block.sh

# Lint
lint:
	flake8 tools/contract_validator --count --select=E9,F63,F7,F82 --show-source --statistics
	black --check tools/contract_validator
	isort --check-only tools/contract_validator
