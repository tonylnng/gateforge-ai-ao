# Adapter — Perplexity Computer (API-based)

> **Class:** API · **Status:** Reference adapter · **Language:** TypeScript (Node)

Perplexity Computer is an API-accessible agent that excels at research, browsing, multi-tool synthesis, and artifact generation. This adapter wraps its API in the AI-AO protocol.

## Capabilities exposed

| Capability             | Notes                                                |
| ---------------------- | ---------------------------------------------------- |
| `research`             | Multi-source web research with cited results         |
| `artifact-generation`  | PDF, DOCX, PPTX, XLSX, markdown reports              |
| `code-review`          | When code context is provided                        |
| `browser-task`         | Page actions via Computer's browser tool             |

## Architecture

```
┌─────────────┐    NATS      ┌─────────────────────┐    HTTPS    ┌────────────────┐
│ Orchestrator│ ───────────▶ │ adapter-pplx (TS)   │ ──────────▶ │ Perplexity API │
└─────────────┘              │  • envelope→request │             └────────────────┘
       ▲                     │  • stream→event     │                     │
       └────── NATS ─────────│  • cost extraction  │ ◀──── webhook ──────┘
                             │  • artifact upload  │
                             └─────────────────────┘
                                       │
                                       ▼
                                ┌──────────────┐
                                │ MinIO (S3)   │
                                └──────────────┘
```

> **For the canonical end-to-end notification flow** (how a NATS message becomes an API call and a webhook becomes a NATS event), see [`docs/AGENT-NOTIFICATION.md`](../../docs/AGENT-NOTIFICATION.md).

## Why a webhook + adapter (not direct callback)

Perplexity Computer can deliver long tasks. Polling is forbidden by AI-AO's third guarantee. So:

1. Adapter starts the task via API and stores the task ID.
2. Adapter exposes a webhook endpoint at `/webhook/pplx`.
3. Computer calls the webhook on progress/completion.
4. Adapter translates webhook → AI-AO event and publishes on NATS.

See [/protocol/WEBHOOK-SPEC.md](../../protocol/WEBHOOK-SPEC.md) for HMAC signing rules.

## Configuration

| Env var                         | Purpose                                |
| ------------------------------- | -------------------------------------- |
| `ADAPTER_PPLX_API_KEY`          | API key for Perplexity Computer        |
| `ADAPTER_PPLX_BASE_URL`         | Override for proxy/staging             |
| `ADAPTER_PPLX_HTTP_PORT`        | Webhook + health port (default 8201)   |

## Cost reporting

Each `completed` event emits:

```json
{
  "cost_usd": 0.0142,
  "tokens": { "input": 1230, "output": 4502 },
  "model": "computer-v1"
}
```

The orchestrator's cost-aggregator consumes these to populate `task_costs` in Postgres.

## Deploy

```bash
docker compose --profile pplx up -d adapter-perplexity-computer
```

## Implementation status

Phase 4 deliverable. The TypeScript SDK (`@aiao/adapter`) is the foundation.
