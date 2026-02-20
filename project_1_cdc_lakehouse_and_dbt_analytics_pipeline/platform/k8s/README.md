# K8s Deployment (Project 1)

## Structure

- **base/**: Common resources (Deployments, Services, ConfigMaps)
- **overlays/**: Environment-specific overrides (dev/stg/prod)

## Deploy

```bash
# Deploy to dev
make deploy-k8s-dev

# Deploy to staging
make deploy-k8s-stg

# Deploy to production
make deploy-k8s-prod

# Or use kustomize directly
kubectl apply -k platform/k8s/overlays/dev
```

## Status

```bash
make status-k8s K8S_OVERLAY=dev
```

## Undeploy

```bash
make undeploy-k8s K8S_OVERLAY=dev
```
