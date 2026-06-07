# DevOps Showcase

A production-grade DevOps pipeline: Terraform → Docker/k3s → GitHub Actions → Prometheus/Grafana.

**Live:** `http://45.32.80.218/health` | Grafana: `http://45.32.80.218:3000` (password: `showcase`)

## Stack

| Layer | Tool |
|---|---|
| Provision | Terraform + Vultr |
| Orchestration | k3s (Kubernetes) |
| CI/CD | GitHub Actions |
| Metrics | Prometheus + recording rules |
| Logs | Loki + Promtail |
| Traces | Tempo + OpenTelemetry (FastAPI auto-instrumentation) |
| Synthetic checks | Blackbox Exporter (probes the public endpoint like a real user) |
| Dashboards | Grafana (RED, SLO error budget, Synthetic Monitoring) — full trace ↔ log ↔ metric correlation |
| Alerting | Alertmanager + Slack webhook |
| Security gate | Cardinality Guard (custom GitHub Action) |

## Quick Start

```bash
# 1. Provision infrastructure
make provision

# 2. Create the Slack webhook secret (Alertmanager reads this at startup)
kubectl create secret generic alertmanager-slack \
  --from-literal=webhook-url='https://hooks.slack.com/services/XXX/YYY/ZZZ' \
  -n monitoring

# 3. Deploy app + monitoring
make deploy

# 4. Open Grafana
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
                │       ├── emits metrics  → Prometheus
                │       ├── emits traces   → Tempo (OTLP/gRPC, auto-instrumented)
                │       └── logs trace_id  → stdout → Promtail → Loki
                ├── Prometheus (scrapes /metrics + recording rules for SLO)
                │       └── Alertmanager (fires to Slack: error rate / p99 / pod down / probe failed)
                ├── Blackbox Exporter (probes /health from OUTSIDE the cluster — real user path)
                ├── Loki + Promtail (pod log aggregation)
                ├── Tempo (distributed tracing backend)
                └── Grafana — fully correlated observability
                        ├── RED dashboard (rate, errors, p99 latency)
                        ├── SLO dashboard (error budget burn rate + live Loki logs)
                        ├── Synthetic Monitoring dashboard (external probe uptime/latency)
                        └── Trace ↔ Log ↔ Metric correlation: click a trace_id in
                            a log line → jump to its span in Tempo, or click a span
                            → jump to the exact log lines that came out of it
```

### Tracing in 30 seconds

The app is instrumented with OpenTelemetry's FastAPI auto-instrumentation — every request gets a trace exported to Tempo over OTLP/gRPC, and the same `trace_id` is printed in the request log line. Promtail ships that line to Loki, and Grafana's Loki↔Tempo `derivedFields`/`tracesToLogsV2` wiring turns it into a one-click jump in either direction — the same workflow you'd use to debug a slow request in production: see the spike on the RED dashboard → open the trace in Tempo → jump straight to the logs that span emitted.

## Incident: synthetic monitoring caught a silent prod outage

While wiring up the blackbox exporter, the new external probe immediately reported `probe_success == 0` for `http://45.32.80.218/health` — yet every internal health check (readiness probes, in-cluster scrape) was green. Root cause: `signal-api`'s `Service` was `type: LoadBalancer`, but k3s's built-in LB (`klipper-lb`) only binds the node's external IP to **one Service per port**, and Traefik already owned `:80`. The Service sat in `<pending>` and the public endpoint had been silently 404ing at the Traefik layer — invisible to every internal check. Fixed by switching `signal-api` to `ClusterIP` and adding an `Ingress` so Traefik routes `/` to it. This is the textbook case for synthetic monitoring: **internal health ≠ what the user actually experiences.**

## TODO

### Phase 2 — Observability (in progress)

- [x] **Alertmanager + Slack webhook** — `PrometheusRule` fires on high error rate, p99 > 500ms, and pod down; Alertmanager routes to Slack
- [x] **Loki + Promtail** — Promtail DaemonSet ships pod logs to Loki; Grafana log panel lets you drill from a metric spike directly to the log lines that caused it (PLG stack)
- [x] **SLO dashboard + error budget** — recording rules pre-aggregate success rate into `job:request_success_rate:rate5m`; second Grafana dashboard shows SLO target, burn rate, and remaining error budget
- [x] **Synthetic monitoring** — blackbox exporter probes `/health` from outside the cluster on the real public path; caught a real silent outage on first deploy (see incident above); `SyntheticProbeFailed` alert wired to Alertmanager

### Phase 3

- [ ] **Close port 6443 to public internet** — deploy self-hosted Actions runner as a pod inside k3s so the API server is never exposed externally. See: [actions-runner-controller](https://github.com/actions/actions-runner-controller)
- [ ] Cardinality Guard Path B — runtime integration test (spin up app + Prometheus via Docker Compose, fire mock traffic, count active series via `/api/v1/series`)
- [ ] HPA (horizontal pod autoscaling) on CPU
- [ ] Helm for monitoring stack (replace raw manifests)
- [ ] Remote Terraform state migration to versioned backend
- [ ] Staging environment with PR previews
