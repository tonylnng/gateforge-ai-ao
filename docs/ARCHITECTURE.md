# Architecture

This document explains the architecture of GateForge AI-AO in depth. For a higher-level overview, see [`README.md`](../README.md). For concept definitions, see [`CONCEPTS.md`](CONCEPTS.md). For the specific question of **how AI-AO notifies agents like Manus or Perplexity Computer**, see [`AGENT-NOTIFICATION.md`](AGENT-NOTIFICATION.md).

---

## Layered view

```mermaid
flowchart TD
    L6["LAYER 6 — INTERFACES\nHumans (Admin Portal, Git UI) · External Triggers"]
    L5["LAYER 5 — METHODOLOGY\nOptional. Maps domain concepts (phases, roles, gates)\nonto AI-AO primitives. e.g. GateForge Guideline.\n★ AI-AO does not require this layer to exist ★"]
    L4["LAYER 4 — ORCHESTRATION\nOrchestrator · Agent Registry · Policy & Verifier Engine\nRouting · SLA enforcement · Audit"]
    L3["LAYER 3 — PROTOCOL\nTask envelope · Events · Agent cards · Error taxonomy\nJSON Schema · SemVer · Conformance suite"]
    L2["LAYER 2 — TRANSPORT\nNATS JetStream · GitHub webhooks · HTTP control API"]
    L1["LAYER 1 — SUBSTRATE\nGitHub (memory) · NATS (nervous system) · MinIO (artifacts)\nPostgres (cost/audit aggregation)\nOTel + Tempo + Loki + Grafana"]

    L6 --> L5 --> L4 --> L3 --> L2 --> L1
```

Lower layers are stable. Higher layers iterate freely. The protocol (Layer 3) is the contract between the lower stack (everyone implements) and the higher stack (everyone consumes).

---

## Component diagram

```mermaid
flowchart TD
    GH["GitHub.com\n(per-project repo)"]

    subgraph CP["AI-AO Control Plane (your VM)"]
        ORCH["Orchestrator (Go service)\n· receives webhooks\n· reads agent registry NATS KV\n· routes tasks by capability\n· subscribes to lifecycle events\n· mirrors significant events to Git\n· enforces policy / budget / circuit breakers"]
        NATS["NATS JetStream\nsubjects: project.*.task.*  agent.*  registry.*  audit.*"]
        NATSKVBOX["NATS KV (registry)"]
        POLICY["Policy Engine"]
        VERIFIER["Verifier Engine"]
        AD_OC["OpenClaw adapter"]
        AD_PC["Perplexity Computer adapter"]
        AD_MN["Manus adapter"]
        AD_CG["ChatGPT Agent adapter"]
        AD_CU["Custom adapter"]

        ORCH -->|pub/sub| NATS
        ORCH -->|KV| NATSKVBOX
        ORCH -->|http| POLICY
        ORCH -->|http| VERIFIER
        NATS --> AD_OC
        NATS --> AD_PC
        NATS --> AD_MN
        NATS --> AD_CG
        NATS --> AD_CU
    end

    subgraph STORAGE["Storage layer"]
        MINIO["MinIO (S3 API)"]
        PG["Postgres (cost, audit)"]
        OTEL["OTel + Tempo + Loki + Grafana"]
    end

    subgraph PLATFORMS["Agent Platforms"]
        OC_VM["OpenClaw VMs"]
        PC_SAAS["Perplexity Computer (SaaS)"]
        MN_SAAS["Manus (SaaS)"]
        CG_SAAS["ChatGPT Agent (SaaS)"]
        CU_SAAS["Custom agent"]
    end

    GH -->|webhooks| ORCH
    ORCH -->|commits| GH
    CP --> STORAGE
    AD_OC -->|"NATS (native)"| OC_VM
    AD_PC -->|HTTPS API| PC_SAAS
    AD_MN -->|Browser automation| MN_SAAS
    AD_CG -->|Browser automation| CG_SAAS
    AD_CU --> CU_SAAS
```

All adapter services and storage components run on **your VM** (single-VM dev) or across a small fleet (production). See [`install/`](../install/) for sizing.

---

## Data flow: a task in motion

```mermaid
sequenceDiagram
    participant Human
    participant GitHub
    participant Orchestrator
    participant NATS
    participant Adapter
    participant Platform
    participant MinIO

    Human->>GitHub: file issue
    GitHub->>Orchestrator: webhook
    Orchestrator->>Orchestrator: pick agent
    Orchestrator->>GitHub: commit task.md
    Orchestrator->>NATS: publish assigned
    NATS->>Adapter: route
    Adapter->>Platform: invoke
    Adapter->>NATS: ack
    NATS->>Orchestrator: accepted
    Platform->>Adapter: result
    Adapter->>MinIO: store artifact
    Adapter->>NATS: publish completed
    NATS->>Orchestrator: completed
    Orchestrator->>GitHub: commit done/T-X.md
    GitHub->>Human: issue closed
```

Every arrow is durable, traced, and audited. The bus carries the live signal; Git carries the durable record; MinIO carries the bytes.

---

## Why three substrates instead of one

Other multi-agent designs typically pick one storage layer and force everything through it. Each choice has a failure mode:

| If you only used… | What breaks |
|-------------------|-------------|
| **Just Git** | Real-time coordination is too slow; no consumer groups; no streaming progress |
| **Just NATS** | No human-readable audit; no version history; no shared world model |
| **Just a database** | No human-AI shared interface; you reinvent issue tracking, file diffs, ACLs |
| **Just S3** | No event semantics; no routing; no audit trail |

Three substrates, each playing to its strengths, costs only modest operational complexity (one extra binary or two) and unlocks order-of-magnitude better behaviour on the dimensions that matter for production multi-agent work.

---

## Trust boundaries

```mermaid
flowchart TD
    EXT["TRUST: LOWEST\nExternal SaaS agents (Perplexity Computer, Manus, etc.)\n· only see what their adapter sends them\n· output validated against schema before re-entering bus\n· per-platform data classification policy enforced"]

    NATIVE["TRUST: MEDIUM\nNative agents (OpenClaw fleet)\n· authenticated to NATS via JWT\n· cannot escape their assigned subject namespace"]

    GH_TRUST["TRUST: HIGH\nGitHub repos\n· branch protection on main\n· GitHub App with fine-grained per-repo permissions\n· signed commits required"]

    CORE["TRUST: HIGHEST\nYour VM (orchestrator, NATS, MinIO, Postgres, adapters)\n· mTLS between services\n· NATS auth via per-agent JWTs\n· Secrets in /opt/secrets/ai-ao.env (never in Git)"]

    EXT -->|"adapter mediates"| NATIVE
    NATIVE -->|"scoped credentials per platform"| GH_TRUST
    GH_TRUST -->|"signed messages, signed commits"| CORE
```

External agents are never trusted directly. Every output crossing back into the trusted core is schema-validated, sanitized, and tagged with provenance.

---

## Failure model

The system is designed to **fail open with audit**, not fail silent.

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Adapter crashes mid-task | NATS heartbeat missed, JetStream redelivery | Same adapter restarts, sees task_id in seen-set, resumes via platform API or re-runs idempotently |
| NATS broker dies | All adapters reconnect on backoff; orchestrator switches to readonly Git mode | Cluster mode in production (3 nodes); single-node dev tolerates restart |
| GitHub webhook missed | 60s reconciliation loop diffs Git state vs NATS KV | Drift detected, missing events synthesized |
| Platform timeout | Adapter SLA timer fires | Task marked failed with `error.timeout`, retry policy applies |
| Verification failure | Verifier publishes `task.failed` with reason | Original task fails, escalation policy fires |
| Cost circuit breaker trips | Policy engine sees daily spend > cap | New tasks rejected with `error.budget_exceeded`; in-flight tasks complete |
| Poison message | JetStream max-deliver exceeded | Routed to DLQ subject, alert fires, manual replay via `tools/replay-cli` |

---

## Scaling model

| Stage | Configuration | Throughput target |
|-------|---------------|-------------------|
| **Dev / personal** | Single VM, all components co-located | ~100 tasks/day, ~5 concurrent |
| **Small team** | Single VM (8c/16GB), tuned | ~10k tasks/day, ~50 concurrent |
| **Production** | 3-node NATS cluster, dedicated MinIO, separate orchestrator and adapter VMs | ~1M tasks/day, ~1000 concurrent |
| **Multi-tenant** | Add per-tenant subject prefix and JWT scopes; horizontal adapters | Scale linearly with adapter count |

Adapters scale horizontally via NATS consumer groups: spin up N instances of the same adapter, NATS distributes work automatically. The orchestrator scales vertically first, then can be sharded by project.

---

## Observability

Every interaction generates:

1. **An OTel trace span** (with parent span propagated via NATS message headers)
2. **A structured log line** (Loki)
3. **A metric** (Prometheus, scraped by Grafana)
4. **An event** (NATS audit firehose, mirrored to Git for projects with audit retention)

The result: you can pick any `task_id` and reconstruct the exact sequence — which agent did what, when, with what cost, with what input and output, in milliseconds.

See [`install/06-observability.md`](../install/06-observability.md) for the stack.

---

## Where to go next

- [`CONCEPTS.md`](CONCEPTS.md) — define every concept
- [`../protocol/PROTOCOL-SPEC.md`](../protocol/PROTOCOL-SPEC.md) — the wire-level contract
- [`../install/`](../install/) — build the stack
- [`ROADMAP.md`](ROADMAP.md) — phase-by-phase build plan
- [`adr/`](adr/) — architectural decisions and their rationale
