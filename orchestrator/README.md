# GateForge AI-AO — Orchestrator

> **Status:** Scaffold (Phase 3 deliverable) · **Language:** Go 1.23 · **Binary size target:** < 30 MB · **Image:** `ghcr.io/tonylnng/gateforge-aiao-orchestrator:0.1.0`

The orchestrator is the **stateless control plane** for AI-AO. It dispatches tasks, enforces policy, aggregates cost, and emits the audit trail. It does **not** store irreplaceable state — Git is the system of record.

## What the orchestrator does

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          ORCHESTRATOR                                   │
│                                                                         │
│   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────────┐    │
│   │ Ingress  │   │ Router   │   │ Watchdog │   │  Cost Aggregator │    │
│   │ (HTTP)   │──▶│ (policy) │──▶│  (timeouts) │ │   (events→PG)   │    │
│   └──────────┘   └─────┬────┘   └──────────┘   └─────────┬────────┘    │
│         │              │                                  │             │
│         │              ▼                                  ▼             │
│         │         NATS publish                       Postgres           │
│         │      (aiao.task.assigned.*)                (rollups)          │
│         │              │                                                 │
│         │              ▼                                                 │
│         │       Adapters consume                                         │
│         │              │                                                 │
│         │              ▼                                                 │
│         │       NATS publish (aiao.event.*)                              │
│         │              │                                                 │
│         ▼              ▼                                                 │
│   Git writer ◀──── Audit signer ──── Audit log mirror (PG)              │
│   (decisions+state)                                                      │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components

| Module             | Purpose                                                       |
| ------------------ | ------------------------------------------------------------- |
| `cmd/orchestrator` | Single binary entrypoint; subcommands for migrations & seed   |
| `ingress/`         | HTTP API for synchronous task submission + control actions    |
| `router/`          | Policy evaluation, agent selection, breaker check             |
| `dispatcher/`      | Publishes `aiao.task.assigned.*` with retry + idempotency     |
| `watchdog/`        | Heartbeat/timeout enforcement; emits `failed` on stalls       |
| `cost/`            | Subscribes to `aiao.event.completed.*`, writes Postgres rollup|
| `audit/`           | Signs decisions with HMAC, mirrors to Git + Postgres          |
| `gitwriter/`       | Pushes audit + state snapshots to the configured Git repo     |
| `policy/`          | Hot-reload of `policy.yaml`; evaluator + budget guard         |
| `internal/db/`     | sqlc-generated Postgres queries                                |
| `internal/nats/`   | JetStream client wrappers (publish, claim, ack)                |

## Restart-safety guarantees

The orchestrator can be killed at any moment. On restart:

1. JetStream replays unacked `TASKS` to in-flight adapters (no work lost).
2. Postgres rollups are derived state — the cost-aggregator catches up by replaying `EVENTS` from its durable consumer offset.
3. Breaker state is loaded from Postgres `breaker_state` table.
4. Policy is loaded from `/config/policy.yaml` (mounted read-only).
5. Git writer reconciles by diffing local audit-log tail vs remote HEAD.

> **There is no in-memory state that, if lost, would corrupt the system.**

## HTTP API (preview)

| Method | Path                           | Purpose                          |
| ------ | ------------------------------ | -------------------------------- |
| POST   | `/v1/tasks`                    | Submit a task                    |
| POST   | `/v1/tasks/:id:cancel`         | Cancel an in-flight task         |
| POST   | `/v1/tasks/:id:redirect`       | Re-route to a different agent    |
| GET    | `/v1/tasks/:id`                | Read current state               |
| POST   | `/v1/control/pause`            | Break-glass: pause all dispatch  |
| POST   | `/v1/control/drain`            | Drain mode (no new tasks)        |
| GET    | `/healthz` / `/readyz`         | Probes                           |
| GET    | `/metrics`                     | Prometheus metrics               |

Exact request/response schemas live in `/protocol/` once Phase 3 is complete.

## Build

```bash
make build        # → bin/orchestrator
make test         # unit + integration tests (in-memory NATS+PG)
make image        # → ghcr.io/tonylnng/gateforge-aiao-orchestrator:dev
```

## Configuration

All runtime config comes from environment variables (see `infrastructure/.env.example`) and the policy YAML at `/config/policy.yaml`. There are **no command-line flags** for behavior — only for one-shot subcommands (`migrate`, `seed`, `version`).

## Phase plan

| Phase | Deliverable                                                  |
| ----- | ------------------------------------------------------------ |
| 1     | Repo + protocol (this commit)                                |
| 2     | Infrastructure compose, observability                         |
| 3     | Orchestrator MVP — ingress, dispatcher, watchdog, cost        |
| 4     | Adapter SDKs (Go + TS) + Perplexity Computer adapter          |
| 5     | OpenClaw + Manus adapters; conformance suite                  |
| 6     | Audit signing, Git writer, ADR enforcement                    |
| 7     | HA — NATS clustering, Postgres replication                    |
| 8     | Admin Portal upgrade (per `docs/ADMIN-PORTAL-UPGRADE.md`)     |
