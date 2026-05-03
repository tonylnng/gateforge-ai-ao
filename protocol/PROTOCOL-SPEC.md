# AI-AO Protocol Specification

**Version:** `1.0.0-draft`
**Status:** Draft — pending Phase 1 finalization
**Last updated:** 2026-05-03

This document defines the wire-level contract for GateForge AI-AO. Every adapter, orchestrator, and SDK consumer MUST conform.

---

## 1. Conventions

- All payloads are JSON (UTF-8).
- All timestamps are ISO 8601 with timezone offset (e.g. `2026-05-03T17:58:00+08:00`).
- All identifiers are **UUIDv7** unless stated otherwise.
- Field names are `snake_case`.
- Versioning is SemVer.
- Unknown fields MUST be ignored (forward compatibility).
- Required fields MUST be present and non-null unless explicitly marked optional.

---

## 2. Object types

The protocol defines four object types:

| Type | Purpose | Schema |
|------|---------|--------|
| **Task envelope** | Unit of delegated work | [`schema/task-envelope.v1.json`](schema/task-envelope.v1.json) |
| **Event** | Lifecycle update on a task | [`schema/event.v1.json`](schema/event.v1.json) |
| **Agent card** | Self-description published by every agent | [`schema/agent-card.v1.json`](schema/agent-card.v1.json) |
| **Error** | Structured failure description | [`schema/error.v1.json`](schema/error.v1.json) |

---

## 3. Task envelope

### Purpose

A self-contained description of a unit of work to be performed by an agent.

### Schema (canonical example)

```json
{
  "envelope_version": "1.0",
  "task_id": "01HXYZAB12CDEF34GHJK56MNPQ",
  "trace_id": "00f067aa0ba902b7-1a2b3c4d5e6f7890",
  "parent_task_id": null,
  "project": "gateforge-travel",
  "created_at": "2026-05-03T17:58:00+08:00",
  "created_by": "agent:openclaw-prime",
  "assigned_to": "agent:perplexity-computer-prod",
  "capability_required": "research",

  "goal": "Research best Southeast Asia destinations for October travel",
  "success_criteria": [
    "Cover at least 5 destinations",
    "Include weather, crowd levels, budget estimate per destination",
    "Cite sources for all claims"
  ],

  "deliverable_type": "markdown_report",
  "deliverable_schema_ref": "protocol/schema/research-report.v1.json",

  "context_refs": [
    "git://gateforge-travel/README.md",
    "git://gateforge-travel/decisions/0007-trip-constraints.md"
  ],

  "constraints": {
    "budget_usd": 1.00,
    "deadline": "2026-05-03T19:00:00+08:00",
    "autonomy_level": "supervised",
    "data_classification": "public",
    "max_attempts": 2
  },

  "verification": {
    "required": true,
    "verifier_capability": "fact-check",
    "policy": "block-on-failure"
  },

  "callback": {
    "events_subject": "project.gateforge-travel.task.01HXYZAB12CDEF34GHJK56MNPQ.events",
    "completion_commit_to": "tasks/done/01HXYZAB12CDEF34GHJK56MNPQ.md"
  },

  "metadata": {
    "gateforge_guideline": {
      "phase": "requirements-research",
      "role": "pm"
    }
  }
}
```

### Field reference

| Field | Required | Type | Description |
|-------|:-:|------|-------------|
| `envelope_version` | yes | string | SemVer of envelope schema. Must match `protocol/version.txt` major. |
| `task_id` | yes | uuidv7 | Globally unique task identifier. Idempotency key. |
| `trace_id` | yes | string | OpenTelemetry trace identifier. |
| `parent_task_id` | no | uuidv7 \| null | Parent task if this is a subtask. |
| `project` | yes | string | Project repo slug (matches GitHub repo name). |
| `created_at` | yes | iso8601 | When the envelope was created. |
| `created_by` | yes | string | `agent:<id>` of creator. |
| `assigned_to` | no | string | `agent:<id>` of intended receiver. May be null for capability-routed tasks. |
| `capability_required` | yes | string | Capability the receiver must advertise. |
| `goal` | yes | string | Plain-English description. Must be self-contained. |
| `success_criteria` | yes | array | Bullet list of conditions for "done". |
| `deliverable_type` | yes | string | Enum: `markdown_report`, `code_patch`, `structured_doc`, `binary_artifact`, `decision_record`, `analysis`, `custom`. |
| `deliverable_schema_ref` | no | string | If `deliverable_type` is `structured_doc` or `custom`, points to a JSON Schema. |
| `context_refs` | no | array | URIs (git://, s3://, https://) the receiver must read first. |
| `constraints.budget_usd` | yes | number | Maximum spend in USD. |
| `constraints.deadline` | yes | iso8601 | Latest acceptable completion time. |
| `constraints.autonomy_level` | yes | enum | `autonomous` \| `supervised` \| `approval-required`. |
| `constraints.data_classification` | yes | enum | `public` \| `internal` \| `confidential` \| `restricted`. |
| `constraints.max_attempts` | no | integer | Default 1. |
| `verification.required` | yes | boolean | Whether output must be verified. |
| `verification.verifier_capability` | conditional | string | Required if `verification.required`. |
| `verification.policy` | conditional | enum | `block-on-failure` \| `flag-only` \| `score-and-record`. |
| `callback.events_subject` | yes | string | NATS subject to publish lifecycle events on. |
| `callback.completion_commit_to` | no | string | Repo path to commit terminal state to. |
| `metadata` | no | object | Methodology-specific extensions. AI-AO ignores. |

### Idempotency rules

- Receivers MUST maintain a seen-set keyed by `task_id` for at least 24 hours.
- A duplicate `task_id` MUST result in a no-op and a republished `task.accepted` event for the original.

---

## 4. Events

### Purpose

Lifecycle updates on a task. Published to NATS subjects defined in [`SUBJECTS.md`](SUBJECTS.md).

### Common envelope

```json
{
  "event_version": "1.0",
  "event_id": "01HXYZBC...",
  "event_type": "task.accepted",
  "task_id": "01HXYZAB...",
  "trace_id": "00f067aa...",
  "agent_id": "perplexity-computer-prod",
  "project": "gateforge-travel",
  "occurred_at": "2026-05-03T17:58:01+08:00",
  "data": { ... },
  "cost_metadata": {
    "tokens_input": 1234,
    "tokens_output": 567,
    "usd": 0.012,
    "vendor": "perplexity",
    "billing_ref": "pplx-req-abc123"
  }
}
```

### Event types

| `event_type` | Direction | Required `data` |
|--------------|-----------|-----------------|
| `task.assigned` | orchestrator → adapter | `assignment_reason` |
| `task.accepted` | adapter → orchestrator | `eta_seconds` |
| `task.rejected` | adapter → orchestrator | `error` (see Error schema), `retryable` |
| `task.progress` | adapter → subscribers | `percent` (0-100), `message`, `partial_artifact_uris` (optional) |
| `task.completed` | adapter → subscribers | `artifact_uris`, `summary` |
| `task.failed` | adapter → subscribers | `error`, `attempts_made` |
| `task.cancelled` | any → subscribers | `reason` |
| `task.input_required` | adapter → orchestrator | `prompt`, `expected_response_schema` |
| `task.input_provided` | orchestrator → adapter | `response` |

### SLAs

| Event | Within |
|-------|--------|
| `task.accepted` | 1 second of `task.assigned` |
| `task.progress` | every 30 seconds during long-running work (or on meaningful change) |
| `task.completed` / `task.failed` | by `constraints.deadline` |

Missing `task.accepted` within SLA triggers automatic re-routing or escalation.

---

## 5. Agent card

### Purpose

Self-description an agent publishes on startup and refreshes periodically. Lives in NATS KV (`registry.agents.<agent_id>`) and is mirrored to `AGENTS.md` per project.

### Schema

```yaml
card_version: "1.0"
agent_id: perplexity-computer-prod
type: external-saas             # native | external-saas | custom
adapter:
  name: pc-adapter
  version: "1.0.0"
  protocol_versions: ["1.0"]
capabilities:
  - name: research
    proficiency: high
  - name: web-browsing
    proficiency: high
  - name: document-generation
    proficiency: medium
cost_profile:
  per_task_estimate_usd: 0.50
  per_token_input_usd: 0.000003
  per_token_output_usd: 0.000015
rate_limits:
  per_minute: 10
  per_hour: 60
  per_day: 500
reliability:
  success_rate_30d: 0.94
  p50_latency_seconds: 60
  p95_latency_seconds: 180
endpoint:
  inbound_subject: "agent.perplexity-computer-prod.inbox"
  outbound_subject: "agent.perplexity-computer-prod.events"
constraints:
  max_concurrent: 3
  default_autonomy_level: supervised
  data_classifications_accepted: ["public", "internal"]
heartbeat:
  interval_seconds: 10
  last_heartbeat: "2026-05-03T17:57:55+08:00"
  current_load: 1
  queue_depth: 0
methodology_hints:
  gateforge_guideline:
    role_fit: ["pm", "qc"]
```

### Lifecycle

1. On startup, adapter publishes its agent card to `registry.agents.<agent_id>` (NATS KV).
2. Adapter heartbeats every 10s; orchestrator considers an agent stale after 60s of silence.
3. On shutdown, adapter publishes a tombstone entry.
4. The card is mirrored to `AGENTS.md` in every project repo where the agent operates, on a 5-minute cadence.

---

## 6. Errors

See [`ERROR-TAXONOMY.md`](ERROR-TAXONOMY.md) for the full catalogue.

### Schema

```json
{
  "error_version": "1.0",
  "code": "platform.rate_limited",
  "message": "Perplexity API returned 429",
  "retryable": true,
  "retry_after_seconds": 60,
  "remediation_hint": "back off and retry; consider increasing rate_limits in agent card",
  "details": {
    "vendor_status": 429,
    "vendor_body": "..."
  }
}
```

---

## 7. Versioning

- Each schema (`task-envelope`, `event`, `agent-card`, `error`) is independently versioned.
- A bump to any schema's MAJOR forces a bump to the protocol MAJOR.
- Adapters declare which protocol versions they speak in their agent card (`adapter.protocol_versions`).
- Orchestrator routes tasks only to adapters that speak a compatible version.

### Compatibility rules

| Change | Required bump |
|--------|---------------|
| New optional field | MINOR |
| New event type | MINOR |
| New error code | MINOR |
| Field semantic clarification (no wire change) | PATCH |
| Required-field added | MAJOR |
| Field renamed or removed | MAJOR |
| Type change | MAJOR |
| New required event in lifecycle | MAJOR |

---

## 8. Conformance

A conforming implementation MUST:

1. Accept every canonical example in this spec without error
2. Emit envelopes that pass `protocol/schema/*.v1.json` validation
3. Honor SLAs in §4
4. Maintain idempotency per §3
5. Pass the conformance test suite in `tools/conformance-test/`

---

## 9. Methodology extension namespace

The `metadata` field on task envelopes and the `methodology_hints` field on agent cards are reserved for methodology-specific data. AI-AO does not interpret these fields. Methodologies SHOULD namespace their fields by methodology name to avoid collision (e.g. `metadata.gateforge_guideline`, `metadata.acme_corp_sdlc`).

---

## 10. Related documents

- [`SUBJECTS.md`](SUBJECTS.md) — NATS subject hierarchy reference
- [`ERROR-TAXONOMY.md`](ERROR-TAXONOMY.md) — error code catalogue
- [`WEBHOOK-SPEC.md`](WEBHOOK-SPEC.md) — standard adapter webhook contract
- [`schema/`](schema/) — JSON Schema source files
