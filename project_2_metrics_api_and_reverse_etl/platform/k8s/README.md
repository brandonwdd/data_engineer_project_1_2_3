# Kubernetes Deployment

## Overview

Project 2 K8s config uses Kustomize; supports dev/stg/prod.

## Layout

```
platform/k8s/
├── base/
│   ├── metrics-api-deployment.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   ├── metrics-api-patch.yaml
    │   └── kustomization.yaml
    └── prod/
        ├── metrics-api-patch.yaml
        └── kustomization.yaml
```

## Deploy

### Dev

```bash
kubectl apply -k platform/k8s/overlays/dev
```

### Prod

```bash
kubectl apply -k platform/k8s/overlays/prod
```

## Components

### Metrics API

- **Deployment**: `metrics-api`
- **Service**: `metrics-api` (ClusterIP)
- **ConfigMap**: `metrics-api-config`

### Resources

**Dev**:
- Replicas: 1
- Memory: 128Mi / 256Mi
- CPU: 50m / 200m

**Prod**:
- Replicas: 3
- Memory: 512Mi / 1Gi
- CPU: 200m / 1000m

## Env vars (ConfigMap)

- `TRINO_HOST`, `TRINO_PORT`, `TRINO_USER`, `TRINO_CATALOG`, `TRINO_SCHEMA`

## Health checks

- **Liveness**: `/health` (30s initial, 10s period)
- **Readiness**: `/health` (10s initial, 5s period)

## Notes

1. Build `metrics-api` image first
2. Ensure Trino is reachable
3. Use different namespaces per env
4. Use Secrets for sensitive data in prod