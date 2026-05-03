# Webhook Specification

For agent platforms that **can** host an HTTP endpoint, AI-AO defines a standard inbound webhook contract that adapters can either implement directly or wrap.

For platforms that **cannot** host webhooks (Perplexity Computer, Manus, ChatGPT Agent), the adapter performs the same role: it subscribes to NATS on the platform's behalf, drives the platform via API or browser, and translates results back. The webhook contract still defines the *shape* of what comes in and goes out.

---

## Inbound webhook (AI-AO → adapter)

### Endpoint

```
POST /v1/events
Content-Type: application/json
Authorization: Bearer <adapter_jwt>
X-AI-AO-Signature: <hmac-sha256 of body using shared secret>
X-AI-AO-Trace-Id: <trace_id>
```

### Body

A standard event payload (see [`PROTOCOL-SPEC.md §4`](PROTOCOL-SPEC.md#4-events)). The most common inbound types:

- `task.assigned` — new work
- `task.input_provided` — response to a previous `input_required`
- `task.cancelled` (control) — orchestrator cancels the task

### Response

```
HTTP 200 OK
{
  "received": true,
  "event_id": "01HXYZBC..."
}
```

The adapter MUST acknowledge within 1 second. Acceptance of the work itself is a separate `task.accepted` event published asynchronously.

Non-200 responses are treated as delivery failures and re-attempted per JetStream retry policy.

---

## Outbound webhook (adapter → AI-AO ingest)

If the adapter cannot publish directly to NATS (e.g. running in a constrained environment), it can POST events to the AI-AO ingest endpoint.

### Endpoint

```
POST /v1/ingest
Content-Type: application/json
Authorization: Bearer <adapter_jwt>
X-AI-AO-Signature: <hmac-sha256 of body using shared secret>
```

### Body

A standard event payload.

### Response

```
HTTP 202 Accepted
```

Ingest endpoint is a thin shim that publishes to NATS on the adapter's behalf. Direct NATS publication is preferred when feasible.

---

## Authentication

- Every adapter receives a JWT signed by the AI-AO control plane on registration
- JWT scope is limited to the agent_id and its allowed subjects
- HMAC signature on every request body (defense-in-depth)
- Rotation: JWTs expire every 30 days; adapter requests fresh JWT via `/v1/auth/rotate` before expiry

---

## TLS

mTLS is the default for adapter-to-control-plane communication. See [`install/10-security.md`](../install/10-security.md) for certificate issuance.

---

## When you don't need webhooks

Native adapters (those using the AI-AO SDK) talk directly to NATS over the cluster network and never hit the webhook surface. Webhooks exist to accommodate adapters that for any reason cannot maintain a persistent NATS connection — typically constrained network environments or simple wrapper services.

For closed platforms (Perplexity Computer, Manus, ChatGPT Agent), the adapter — running on **your VM** — speaks NATS natively. The closed platform itself never sees AI-AO's webhook surface; it just sees whatever native interface (API call, browser session) the adapter uses.
