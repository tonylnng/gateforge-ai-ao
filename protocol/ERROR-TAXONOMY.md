# Error Taxonomy

Structured error codes used in `task.rejected` and `task.failed` events.

---

## Code structure

```
<category>.<specific>
```

Categories: `protocol`, `platform`, `policy`, `verification`, `internal`.

---

## Catalogue

### `protocol.*` — protocol-level errors

| Code | Meaning | Retryable | Notes |
|------|---------|:-:|------|
| `protocol.invalid_envelope` | Envelope failed schema validation | no | Fix sender |
| `protocol.unsupported_version` | Adapter does not speak this protocol version | no | Routing should never reach this; bug |
| `protocol.unknown_capability` | Capability not advertised by this agent | no | Routing bug |
| `protocol.duplicate_task_id` | Already seen this task_id | no | Idempotency caught it |

### `platform.*` — vendor/platform errors

| Code | Meaning | Retryable | Notes |
|------|---------|:-:|------|
| `platform.rate_limited` | Vendor returned 429 or equivalent | yes | Set `retry_after_seconds` |
| `platform.timeout` | Vendor did not respond in time | yes | Backoff before retry |
| `platform.auth_failed` | Vendor credentials invalid or expired | no | Operator must rotate |
| `platform.unavailable` | Vendor service down or degraded | yes | Circuit breaker may engage |
| `platform.bad_response` | Vendor returned malformed output | yes (limited) | If repeated, fail terminally |
| `platform.session_expired` | Browser-based platform lost session | yes | Adapter re-authenticates |

### `policy.*` — policy violations

| Code | Meaning | Retryable | Notes |
|------|---------|:-:|------|
| `policy.budget_exceeded` | Daily / project budget cap reached | no | Operator escalation |
| `policy.data_classification_violation` | Task data class not accepted by agent | no | Re-route to compliant agent |
| `policy.autonomy_required` | Task autonomy level requires approval not granted | no | Wait for human approval |
| `policy.circuit_breaker_open` | Agent or platform suspended due to repeated failures | yes (later) | Auto-reset after window |
| `policy.deadline_exceeded` | Constraint deadline passed before completion | no | Caller may re-create with new deadline |

### `verification.*` — verifier results

| Code | Meaning | Retryable | Notes |
|------|---------|:-:|------|
| `verification.factual_error` | Verifier found unsupported claims | maybe | Per `verification.policy` |
| `verification.schema_mismatch` | Output did not match declared `deliverable_schema_ref` | yes | Ask agent to retry with stricter prompt |
| `verification.success_criteria_unmet` | Output did not meet listed success criteria | yes | Retry or escalate |
| `verification.unsafe_output` | Safety check flagged content | no | Block, log, escalate |

### `internal.*` — AI-AO internal failures

| Code | Meaning | Retryable | Notes |
|------|---------|:-:|------|
| `internal.broker_disconnected` | NATS connection lost mid-task | yes | Auto-reconnect, redeliver |
| `internal.storage_unavailable` | MinIO write failed | yes | Operator alert |
| `internal.git_failure` | GitHub commit failed | yes | Reconciliation will retry |
| `internal.adapter_crashed` | Adapter process died mid-task | yes | JetStream redelivery |
| `internal.unknown` | Unhandled exception | maybe | Always alert |

---

## Retry policy

Default per category:

| Category | Default retry | Default backoff |
|----------|---------------|-----------------|
| `protocol.*` | 0 (terminal) | n/a |
| `platform.*` | 3 | exponential, base 5s, max 60s |
| `policy.*` | 0 unless explicitly retryable | n/a |
| `verification.*` | per `verification.policy` | n/a |
| `internal.*` | 3 | exponential, base 5s, max 60s |

Per-task override via `constraints.max_attempts`.

---

## DLQ

Tasks that exhaust retries are routed to `project.<project>.task.<task_id>.dlq` and the JetStream `DLQ` stream. Operators triage via `tools/replay-cli`.
