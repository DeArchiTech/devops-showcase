# DevOps Showcase

A production-grade DevOps pipeline: Terraform → Docker/k3s → GitHub Actions → Prometheus/Grafana.

**Live:** `http://45.32.80.218/health` | Grafana: `http://45.32.80.218:3000` (password: `showcase`)

## Stack

| Layer | Tool |
|---|---|
| Provision | Terraform + Vultr |
| Orchestration | k3s (Kubernetes) |
| CI/CD | GitHub Actions |
| Metrics | Prometheus |
| Dashboards | Grafana (pre-provisioned RED dashboard) |
| Security gate | Cardinality Guard (custom GitHub Action) |

## Quick Start

```bash
# 1. Provision infrastructure
make provision

# 2. Deploy app + monitoring
make deploy

# 3. Open Grafana
make monitor
```

## Cardinality Guard

A custom GitHub Action at `.github/actions/cardinality-guard/` that scans Python source files for Prometheus metric definitions with high-cardinality label names and fails the build before they reach production.

High-cardinality labels (e.g. `user_id`, `request_id`, `email`) create one time series per unique value — causing Prometheus memory exhaustion at scale.

```
cardinality-guard → build → deploy
```

## Architecture

```
GitHub Push
    │
    ├── Cardinality Guard (AST scan — fails build on bad labels)
    ├── Docker build → push to GHCR
    └── kubectl rollout → k3s on Vultr VPS
                │
                ├── signal-api pod (FastAPI, non-root, resource limits)
                ├── Prometheus (scrapes /metrics every 15s)
                └── Grafana (RED dashboard: rate, errors, p99 latency)
```

## TODO

### Phase 2

- [ ] **Close port 6443 to public internet** — currently open to `0.0.0.0/0` for kubectl access from GitHub Actions runners. Fix: deploy a self-hosted Actions runner as a pod inside k3s so the API server is only accessed on the internal cluster network, never exposed externally. See: [actions-runner-controller](https://github.com/actions/actions-runner-controller)
- [ ] Cardinality Guard Path B — runtime integration test (spin up app + Prometheus via Docker Compose, fire mock traffic, count active series via `/api/v1/series`)
- [ ] HPA (horizontal pod autoscaling) on CPU
- [ ] Helm for monitoring stack (replace raw manifests)
- [ ] Alert rules + Alertmanager
- [ ] Remote Terraform state migration to versioned backend
- [ ] Staging environment with PR previews
