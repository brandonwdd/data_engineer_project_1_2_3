PLATFORM := platform/local
COMPOSE := docker compose -f $(PLATFORM)/docker-compose.yml
K8S_BASE := platform/k8s
K8S_OVERLAY ?= dev

.PHONY: up down reset bronze-up bronze-run test-bronze deploy-k8s deploy-k8s-dev deploy-k8s-stg deploy-k8s-prod

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

reset: down
	$(COMPOSE) down -v
	$(COMPOSE) up -d

# Bronze: MinIO + Spark. Start infra, then run ingest.
bronze-up:
	$(COMPOSE) --profile bronze up -d
	@echo "Wait ~15s for MinIO + minio-init (bucket warehouse). Then: make bronze-run"

bronze-run:
	$(COMPOSE) --profile bronze run --rm spark

# Unit tests (parse + contract validate). Run from project root.
test-bronze:
	PYTHONPATH=. python -m pytest streaming/spark/tests -v

# Acceptance tests
test-acceptance:
	@bash scripts/test_acceptance.sh

# Idempotency test (requires running environment)
test-idempotency:
	@bash scripts/test_idempotency.sh 3

# Generate test evidence package
test-evidence:
	@bash scripts/generate_test_evidence.sh

# Run all tests
test-all: test-bronze test-acceptance
	@echo "All tests completed. Check evidence/validation/ for reports."

# K8s deployment (Kustomize)
deploy-k8s:
	@echo "Deploying to $(K8S_OVERLAY) environment..."
	kubectl apply -k $(K8S_BASE)/overlays/$(K8S_OVERLAY)

deploy-k8s-dev:
	$(MAKE) deploy-k8s K8S_OVERLAY=dev

deploy-k8s-stg:
	$(MAKE) deploy-k8s K8S_OVERLAY=stg

deploy-k8s-prod:
	$(MAKE) deploy-k8s K8S_OVERLAY=prod

# K8s undeploy
undeploy-k8s:
	kubectl delete -k $(K8S_BASE)/overlays/$(K8S_OVERLAY)

# K8s status
status-k8s:
	kubectl get pods -n project1-cdc-$(K8S_OVERLAY)
	kubectl get svc -n project1-cdc-$(K8S_OVERLAY)

# Storage backend switching
switch-to-s3:
	@echo "Switching to S3 (from Terraform outputs)..."
	@bash scripts/switch_to_s3.sh
	@echo "Configuration saved to .env.s3"
	@echo "Source it: source .env.s3"

switch-to-minio:
	@echo "Switching to MinIO (local)..."
	@bash scripts/switch_to_minio.sh
	@echo "Configuration saved to .env.minio"
	@echo "Source it: source .env.minio"
