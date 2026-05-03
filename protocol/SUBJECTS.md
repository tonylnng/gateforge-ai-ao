# NATS Subject Hierarchy Reference

This document is the authoritative reference for every NATS subject used by AI-AO.

---

## Naming convention

```
<scope>.<entity>.<id>.<aspect>
```

- All segments lowercase
- IDs are UUIDv7 or short slugs (project name, agent id)
- Hierarchical wildcards: `*` matches one segment, `>` matches any depth

---

## Subject map

```
project.<project>.task.<task_id>.assigned        ← orchestrator → adapter
project.<project>.task.<task_id>.accepted        ← adapter → orchestrator
project.<project>.task.<task_id>.rejected        ← adapter → orchestrator
project.<project>.task.<task_id>.progress        ← adapter → subscribers (streaming)
project.<project>.task.<task_id>.completed       ← adapter → subscribers (terminal)
project.<project>.task.<task_id>.failed          ← adapter → subscribers (terminal)
project.<project>.task.<task_id>.cancelled       ← adapter → subscribers (terminal)
project.<project>.task.<task_id>.input_required  ← adapter → orchestrator
project.<project>.task.<task_id>.input_provided  ← orchestrator → adapter
project.<project>.task.<task_id>.control         ← orchestrator → adapter (cancel, redirect)
project.<project>.task.<task_id>.dlq             ← any → DLQ (max-deliver exceeded)

agent.<agent_id>.inbox                           ← direct messages to an agent
agent.<agent_id>.events                          ← agent's outbound event stream
agent.<agent_id>.heartbeat                       ← every 10s, liveness + load

registry.agents.announce                         ← agent publishes its card on startup
registry.agents.tombstone                        ← agent publishes shutdown
registry.agents.query                            ← capability discovery requests
registry.agents.query.reply                     ← responses to discovery queries

audit.<project>                                  ← firehose of all events for a project
trace.<trace_id>                                 ← OTel trace correlation
```

---

## JetStream stream definitions

Streams are configured in `infrastructure/nats/jetstream-streams.yaml`. Summary:

| Stream | Subjects | Retention | Storage |
|--------|----------|-----------|---------|
| `TASKS` | `project.*.task.>` | 30 days | file |
| `AGENTS` | `agent.>` | 7 days | file |
| `REGISTRY` | `registry.>` | 7 days | file |
| `AUDIT` | `audit.>` | 365 days | file |
| `DLQ` | `*.dlq` | 30 days | file |

KV buckets:

| Bucket | Purpose | TTL |
|--------|---------|-----|
| `agents` | Live agent registry (current cards) | none |
| `seen` | Idempotency seen-set (`task_id` → ack) | 24h |
| `task_state` | Latest known state of every task | none |
| `policy` | Live policy snapshot | none |

---

## Wildcard subscriptions

Common subscription patterns:

| Subscriber | Subject pattern |
|------------|-----------------|
| Orchestrator (all task events for a project) | `project.<project>.task.*.>` |
| Admin Portal (all events, all projects) | `project.>` + `agent.>` + `registry.>` |
| Audit logger | `audit.>` |
| Agent (its own inbox + control) | `agent.<id>.inbox` + `agent.<id>.control` |

---

## Permissions model

NATS auth uses per-agent JWTs. Each adapter is granted:

- **Publish** to `agent.<own_id>.events`, `agent.<own_id>.heartbeat`, `project.*.task.*.{accepted,rejected,progress,completed,failed,input_required}`
- **Subscribe** to `agent.<own_id>.inbox`, `agent.<own_id>.control`, `project.*.task.*.assigned`

Orchestrator gets a broader JWT covering `project.>`, `agent.>`, `registry.>`, `audit.>`.

The Admin Portal gets a read-only JWT covering subscribe-everything.

See [`install/10-security.md`](../install/10-security.md) for issuance.
