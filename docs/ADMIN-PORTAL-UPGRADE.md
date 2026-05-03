# Admin Portal — Upgrade Plan for AI-AO

> **Audience:** maintainers of [`gateforge-admin-portal-site`](https://github.com/tonylnng/gateforge-admin-portal-site) (Next.js 14 + Express + SQLite + SSE).
>
> **Goal:** evolve the current "Read-Only Operational Control Tower" into the **Operational Control Plane** for GateForge AI-AO — keeping its strengths (clean UX, SSE freshness) while replacing pieces that no longer fit.

---

## TL;DR — what changes, at a glance

```
Current Admin Portal                          Upgraded Admin Portal (AI-AO-aligned)
─────────────────────────                     ───────────────────────────────────────

┌─────────────────────────┐                   ┌──────────────────────────────────────┐
│  Next.js 14 (UI)        │                   │  Next.js 14 (UI)                     │
│  Express backend        │                   │  Express backend (control-plane only)│
│  ── reads ──             │                   │  ── reads via NATS+PG ──             │
│  SQLite (read model)    │                   │  ❌ SQLite removed                    │
│  SSE proxy              │                   │  ✅ NATS subscribe (server-side)      │
│  Static "tower" view    │                   │  ✅ Two-way control actions           │
└─────────────────────────┘                   │  ✅ Trace + cost + verification views │
                                              │  ✅ Git-as-source-of-record reads     │
                                              └──────────────────────────────────────┘

         What stays                    What changes                      What's added
         ──────────                    ────────────                      ────────────
         Next.js 14 + Tailwind         SQLite → consume AI-AO PG          Control actions API
         SSE pattern (UI side)         SSE → nats.ws subscribe            Cost & Budget module
         Auth model                    Health probes → AI-AO /healthz     Trace Explorer (Grafana iframe)
                                                                          Verification Dashboard
                                                                          Policy editor (read-only first)
```

---

## Why upgrade — the gap

The current portal was designed when GateForge was a **single-stack** project:

- It owned its own SQLite read model.
- It received "operational" data via a custom SSE proxy.
- It was strictly read-only by design.

AI-AO changes the world:

- The **system of record is Git** (audit + state). The portal must read from Git for durable views.
- The **real-time bus is NATS JetStream**. The portal must subscribe directly — its current bespoke SSE pipe cannot expose envelope semantics, durable replay, or ack offsets.
- The **rollups live in Postgres** owned by the orchestrator. SQLite is now a duplicate read model that drifts.
- Operators want **two-way control** (cancel, redirect, approve, pause) — not just a dashboard.

We do not throw the portal away. We **promote it**.

---

## Target architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          UPGRADED ADMIN PORTAL                              │
│                                                                             │
│  ┌──────────────────────────┐         ┌──────────────────────────────────┐  │
│  │ Next.js 14 (App Router)  │ ──────▶ │ Server Actions / Route Handlers  │  │
│  │  • React Server Comps    │  fetch  │  • call orchestrator HTTP API    │  │
│  │  • SSE consumer (UI)     │         │  • verify NATS subscription auth │  │
│  └────────────┬─────────────┘         └────────────────┬─────────────────┘  │
│               │                                         │                    │
│               │ EventSource (SSE relay)                 ▼                    │
│               │                       ┌────────────────────────────────────┐ │
│               │                       │ Express service (NEW responsibility)│ │
│               │                       │  • subscribes to aiao.event.>       │ │
│               │                       │  • re-emits SSE for browsers        │ │
│               │                       │  • read aggregates from PG          │ │
│               │                       │  • read durable state from Git      │ │
│               │                       └─────┬───────────────┬───────────────┘ │
│               │                             │               │                 │
└───────────────┼─────────────────────────────┼───────────────┼─────────────────┘
                │                             │               │
                │                             ▼               ▼
        ┌───────▼────────┐        ┌──────────────────┐  ┌──────────────────────┐
        │ Browser users  │        │ NATS JetStream    │  │ Postgres (orch-owned)│
        └────────────────┘        │  aiao.event.>     │  │  task_costs          │
                                  └──────────────────┘  │  audit_log           │
                                                        │  breaker_state       │
                                                        └──────────────────────┘

                                  ┌──────────────────┐
                                  │ Git (system of   │  read-only via gh API  ◀─┐
                                  │  record)         │  for ADRs, audits      │ │
                                  └──────────────────┘                          │
                                                                                │
                                  ┌──────────────────┐                          │
                                  │ Orchestrator API │  control actions only ◀──┘
                                  │ /v1/...          │
                                  └──────────────────┘
```

### Three integration surfaces

| Surface           | Direction | Purpose                                       |
| ----------------- | --------- | --------------------------------------------- |
| **NATS subscribe** | inbound  | Live events (task lifecycle, cost, audit)     |
| **Postgres read** | inbound  | Aggregated rollups (cost charts, budget bars) |
| **Git read**      | inbound  | Durable state — ADRs, audit signed records   |
| **Orchestrator API** | outbound | Control actions: cancel, redirect, pause   |

---

## What to remove

### 1. SQLite read model (replace, do not migrate)

Current SQLite is a **derived** view. It has no value AI-AO Postgres + Git don't already give us. Remove the dependency entirely:

```diff
- import Database from "better-sqlite3";
- const db = new Database("./read-model.db");
+ import { Pool } from "pg";
+ const pool = new Pool({ connectionString: process.env.AIAO_PG_DSN });
```

Migration steps:
1. Add `AIAO_PG_DSN`, `AIAO_NATS_URL`, `AIAO_ORCH_URL` to portal env.
2. Replace each SQLite query with either a PG query (rollups), an NATS subscription (live), or a Git read (durable).
3. Delete `*.sqlite`, the read-model writer, the migration scripts.
4. Drop `better-sqlite3` from `package.json`.

### 2. Bespoke SSE proxy (rebuild on top of NATS)

Keep the **browser-facing SSE endpoint** — Next.js is happy with `EventSource`. Replace its source: subscribe to NATS in the Express layer and forward filtered events.

```ts
// Server-side: Express
import { connect } from "nats";
const nc = await connect({ servers: process.env.AIAO_NATS_URL });
app.get("/events/:taskId", async (req, res) => {
  res.writeHead(200, { "Content-Type": "text/event-stream" });
  const sub = nc.subscribe(`aiao.event.>`, { queue: req.ip });
  for await (const m of sub) {
    if (m.subject.includes(req.params.taskId)) {
      res.write(`data: ${m.string()}\n\n`);
    }
  }
});
```

### 3. Polling code paths

Audit every interval/`setInterval`. AI-AO's third guarantee is **no polling**. Anything you currently `setInterval`-poll is a bug — convert to subscription.

---

## What to add

### Module 1 — Task Lifecycle

The flagship view. One row per task, live from NATS, drilldown to per-event timeline.

```
┌──────────────────────────────────────────────────────────────────┐
│ Tasks                                              [filter: live]│
├──────────────────────────────────────────────────────────────────┤
│ ID            Capability    Agent         State      Age     ▾  │
│ 7f3...        research      pplx/v1       running    00:04    >│
│ 9a2...        code-review   manus/v1      completed  00:32    >│
│ b1c...        system-design openclaw/v1   failed     00:21    >│
└──────────────────────────────────────────────────────────────────┘

Click row → Timeline:
  ▸ assigned       (00:00)
  ▸ started        (00:00.142)
  ▸ progress 25%   (00:01.520)
  ▸ progress 60%   (00:02.890)
  ▸ completed      (00:04.110) — cost $0.0142, tokens 1230/4502
```

### Module 2 — Cost & Budget

Bar charts driven by `task_costs` rollups. Surface budget caps from `policy.yaml`.

```
Daily spend     [█████████░░░░░░░░░░░] 24.10 / 50.00 USD   (cap)
By agent
  pplx/v1       [███████████░░░░░░░░░] 14.30 / 25.00 USD
  openclaw/v1   [██░░░░░░░░░░░░░░░░░░]  2.40
  manus/v1      [██████░░░░░░░░░░░░░░]  7.40 / 10.00 USD
```

### Module 3 — Trace Explorer

**Embed Grafana** via iframe with the **AI-AO Task Explorer** dashboard pre-loaded. Pass `?var-task_id=<id>`. Re-uses all observability investment; no parallel build.

### Module 4 — Verification Dashboard

For the GateForge Guideline workflow that promotes artifacts to Git: show diff, verification checks (lint, tests, ADR present), and an **Approve / Reject** action that calls the orchestrator's `/v1/tasks/:id:redirect`.

```
Pending verification (3)
  ▸ task 7f3...   research bundle   [3 files, 24 KB]
       ✓ schema valid   ✓ ADR linked   ✗ test missing   [Approve] [Reject]
```

### Module 5 — Policy Viewer (read-only Phase 1; editor Phase 2)

Render `policy.yaml` from Git; show effective routing per capability; in Phase 2, allow PR-based edits (portal opens a draft PR, never writes directly).

### Module 6 — Control Actions

Operator-facing buttons that call orchestrator HTTP:

| UI control               | Calls                                |
| ------------------------ | ------------------------------------ |
| Cancel task              | `POST /v1/tasks/:id:cancel`          |
| Redirect task            | `POST /v1/tasks/:id:redirect`        |
| Pause agent              | `POST /v1/control/agent-pause`       |
| Resume agent             | `POST /v1/control/agent-resume`      |
| Global pause / drain     | `POST /v1/control/pause` / `:drain`  |

Every action requires a confirmation modal **and** is logged via the orchestrator's audit pipeline — so the portal never owns the audit story.

---

## Authorization & safety

The current portal's auth model is fine for read-only. With control actions in scope:

- **Roles:** `viewer`, `operator`, `admin`. Mapped to GitHub team membership (use the GitHub OAuth provider).
- **Action gating:** every control endpoint in Express must require role ≥ `operator`. The orchestrator does **not** trust the portal — it independently re-checks the JWT issued by the portal's auth provider.
- **Confirmation friction:** destructive actions (drain, agent-pause for production agents) need a typed confirmation (`type "DRAIN" to confirm`).

---

## Phased migration plan

| Phase | Deliverable                                                                          | Risk level |
| ----- | ------------------------------------------------------------------------------------ | ---------- |
| **A** | Add NATS subscriber to Express (parallel with SQLite). Live tail in dev.             | low        |
| **B** | Add PG read for cost rollups. Build Cost & Budget module.                            | low        |
| **C** | Replace SSE proxy source from SQLite to NATS. Delete SQLite.                         | medium     |
| **D** | Add Trace Explorer (Grafana embed).                                                  | low        |
| **E** | Add control actions (read-only feature flag → operator role gate).                   | high       |
| **F** | Add Verification Dashboard.                                                          | medium     |
| **G** | Add Policy Viewer; later, PR-based editor.                                           | low        |

Each phase is a separate PR, behind a feature flag, with a smoke test that runs against the AI-AO compose stack.

---

## Endpoints the portal must consume (from AI-AO)

| URL                                              | Purpose                            |
| ------------------------------------------------ | ---------------------------------- |
| `nats://<host>:4222`  (subjects `aiao.event.>`)  | Live event stream                  |
| `postgres://aiao@<host>/aiao` (read-only role)   | Cost / audit / breaker rollups     |
| `https://<host>/v1/tasks` (orchestrator)         | Control actions                    |
| `https://<host>:3000/d/aiao-task-explorer`       | Embedded Grafana dashboard         |
| GitHub API (via existing portal OAuth)           | Read ADRs and signed audit records |

A read-only PG role is provisioned with:

```sql
CREATE ROLE portal_ro WITH LOGIN PASSWORD '...';
GRANT CONNECT ON DATABASE aiao TO portal_ro;
GRANT USAGE ON SCHEMA public TO portal_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO portal_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO portal_ro;
```

---

## Open design questions (answer before Phase E)

1. **Single-tenant vs multi-tenant** — does one portal govern multiple AI-AO deployments? If yes, the portal needs a "deployment" selector and per-deployment NATS/PG/Git config.
2. **Mobile UX** — operators on call. Is the Cancel button reachable from a phone in 3 taps? (recommend: yes — Phase F).
3. **Self-service approvals via Slack** — if "approval" becomes a frequent action, the portal might *publish* an approval-required event and let an external Slack bot resolve it. The portal still owns the audit-trail render.
4. **Domain** — current portal is `gateforge.toniclab.ai`. Keep it; the URL is part of muscle memory. Add a small "AI-AO" badge in the header.

---

## Non-goals (explicit)

- The portal is **not** the system of record. Never write durable state to its own DB.
- The portal is **not** an orchestrator. It cannot dispatch tasks directly — it only asks the orchestrator to.
- The portal is **not** an alerting system. Alerts live in Grafana / on-call paging — the portal **shows** alerts but does not trigger pages.

---

## Next concrete step

Open a tracking issue in `gateforge-admin-portal-site` titled **"AI-AO upgrade — Phase A: NATS subscriber"** and link it back to this document. Phase A is unblocked the moment AI-AO Phase 2 (infrastructure) ships.
