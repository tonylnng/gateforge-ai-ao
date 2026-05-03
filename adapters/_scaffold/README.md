# Adapter Scaffold — How to build an AI-AO adapter

> **Use this as the starting point for any new adapter.** Copy the directory, rename, and follow the checklist.

```
adapters/_scaffold/
├── README.md                this file
├── agent-card.yaml          declarative metadata (capabilities, limits)
├── Dockerfile               minimal container scaffold
├── docker-compose.fragment.yml   drop-in service block
├── src/                     example handler skeleton (Go)
├── tests/
│   ├── conformance/         protocol conformance suite (must pass)
│   └── chaos/               crash/restart/reorder tests
└── .env.example
```

## Three classes of adapter

| Class            | Examples                  | How it talks to AI-AO                                     |
| ---------------- | ------------------------- | ---------------------------------------------------------- |
| **Native**       | OpenClaw                  | Direct NATS pub/sub — fastest, lowest overhead             |
| **API-based**    | Perplexity Computer       | HTTP/SDK calls + adapter translates to/from envelope       |
| **Browser-based**| Manus                     | Playwright/CDP automation, session reuse, event scraping   |

You will pick **one** class and ship the adapter as a self-contained Docker container.

## Mandatory contract

Every adapter MUST:

1. **Implement the protocol** — see [/protocol/PROTOCOL-SPEC.md](../../protocol/PROTOCOL-SPEC.md). Subscribe to `aiao.task.assigned.<agent_id>.>`, publish `aiao.event.>`.
2. **Validate every envelope** against `/protocol/schema/task-envelope.v1.json` before processing.
3. **Acknowledge immediately** (NATS ack) — work happens asynchronously.
4. **Emit lifecycle events** — `started`, `progress` (≥ every 30s for tasks > 60s), `completed` OR `failed`.
5. **Be idempotent on `Nats-Msg-Id`** — duplicates within 5 minutes are deduped by JetStream; you must still tolerate later duplicates.
6. **Report cost & tokens** in the `completed` event when applicable.
7. **Pass the conformance suite** in `tests/conformance/` before being added to the official adapter list.

## Mandatory artifacts on disk

| File                                | Purpose                                                       |
| ----------------------------------- | ------------------------------------------------------------- |
| `agent-card.yaml`                   | Capabilities + limits — orchestrator reads on registration    |
| `Dockerfile`                        | Pinned base image, non-root user, healthcheck                 |
| `docker-compose.fragment.yml`       | Copy-paste into top-level compose                             |
| `tests/conformance/run.sh`          | One-shot conformance runner                                   |

## Build it in 6 steps

```text
1. cp -r adapters/_scaffold adapters/<your-name>
2. Edit agent-card.yaml      → list real capabilities, set limits
3. Implement handler         → src/handler.{go,ts,py}
4. Build image               → docker build -t aiao-adapter-<name> .
5. Add docker-compose entry  → see fragment file
6. Run conformance           → tests/conformance/run.sh
```

## Conformance suite (preview)

The conformance harness publishes a series of probes and asserts your adapter:

- ✅ acks within 100 ms
- ✅ emits `started` within 1 s
- ✅ emits `progress` ≥ every 30 s for synthetic long tasks
- ✅ emits `completed` with valid cost/token fields
- ✅ honors `cancel` mid-flight within 5 s
- ✅ idempotent on duplicate `Nats-Msg-Id`
- ✅ rejects malformed envelopes with a typed error from `/protocol/ERROR-TAXONOMY.md`

A passing run produces `conformance-report.json` you can attach to your PR.

## Common pitfalls

- **Polling external APIs** — never poll inside the adapter; instead, subscribe to webhooks or use the SDK's event stream. AI-AO is event-driven end-to-end.
- **Logging secrets** — adapters MUST redact tokens/keys from logs before shipping to OTel.
- **Long handler with no progress** — a 10-minute task that emits one `started` then sits silent will be killed by the orchestrator's heartbeat watchdog.
- **Skipping `completed`/`failed`** — orchestrator times out at the policy `timeout_seconds`; always emit a terminal event.

See the three reference adapters (`openclaw/`, `perplexity-computer/`, `manus/`) for working examples.
