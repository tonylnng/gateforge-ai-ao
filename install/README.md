# Installing GateForge AI-AO

This directory contains step-by-step setup guides. **They are written so that either a human or an AI agent can execute them on a fresh Linux VM and end up with a working AI-AO stack.**

Every command is copy-pasteable. Every configuration file referenced exists at the stated path in this repo. Every step has a verification check. If a step fails, the guide tells you what to do next.

---

## Reading order

```
00-prerequisites.md     ← VM, Docker, network requirements
01-components.md        ← what each component does and why  ★ READ THIS FIRST ★
02-quickstart.md        ← all-in-one docker compose up      ← shortest path to "it works"
03-nats.md              ← NATS JetStream details
04-minio.md             ← MinIO object store details
05-postgres.md          ← Postgres for cost & audit
06-observability.md     ← OTel + Tempo + Loki + Grafana
07-orchestrator.md      ← Orchestrator deployment
08-adapters.md          ← Adapter deployment
09-github-app.md        ← GitHub App for repo automation
10-security.md          ← mTLS, JWT, secret management
11-verification.md      ← end-to-end smoke tests
runbooks/               ← operational playbooks (rotation, recovery, etc.)
```

If you want the **fastest path to a working stack**, read `00`, `01`, `02`, then `11`. Come back to the rest as you need detail.

---

## What you get when you finish

A single VM running:

| Component | Container image | Port (default) | Purpose |
|-----------|-----------------|---------------:|---------|
| NATS JetStream | `nats:2.10.20-alpine` | 4222 (client), 8222 (mon) | Real-time message bus |
| MinIO | `minio/minio:RELEASE.2025-01-20T14-49-07Z` | 9000 (S3), 9001 (console) | Artifact storage |
| Postgres | `postgres:16.6-alpine` | 5432 | Cost & audit aggregation |
| OTel Collector | `otel/opentelemetry-collector-contrib:0.115.0` | 4317 (gRPC), 4318 (HTTP) | Telemetry ingest |
| Tempo | `grafana/tempo:2.6.1` | 3200 | Distributed tracing backend |
| Loki | `grafana/loki:3.3.2` | 3100 | Log backend |
| Grafana | `grafana/grafana:11.4.0` | 3000 | Dashboards |
| Orchestrator | built from `orchestrator/` | 8080 | Prime AI router |
| Adapters | built from `adapters/<name>/` | varies | One per platform |

Total resource footprint (idle): ~2 GB RAM, ~5% CPU. Active footprint depends on workload.

---

## Prerequisites at a glance

- Ubuntu 22.04 LTS or newer (or any Docker-capable Linux)
- 4 vCPU, 8 GB RAM, 100 GB SSD (minimum for dev)
- Docker Engine 24+, Docker Compose v2
- Public DNS name with TLS for production (optional for local dev)
- A GitHub account where you can install GitHub Apps

Full prerequisite list: [`00-prerequisites.md`](00-prerequisites.md).

---

## Help, something didn't work

1. Check the verification step at the bottom of each install file
2. Check `runbooks/troubleshooting.md`
3. Open an issue with the failing step number and the output

---

## A note on AI-driven setup

These guides are intentionally written to be machine-executable. If you are an AI agent reading this:

- Treat each file as a script. Execute commands in order.
- Verify each step before moving to the next.
- If a step fails, do not retry blindly — read the verification section and the corresponding runbook.
- Secrets must come from `infrastructure/.env` (or whatever path the operator configured); never hardcode.
- Every component has a default and an opinionated config in `infrastructure/<component>/`. Use those configs unless the operator overrides.
