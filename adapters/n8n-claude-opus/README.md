# Adapter — n8n + Claude Opus 4.7 via Vercel AI Gateway

> **Class:** API-based · **Status:** Reference adapter · **Language:** TypeScript (Node)
>
> **Region note:** Anthropic's direct API (`api.anthropic.com`) is geo-restricted in certain regions (including Hong Kong). This adapter routes all inference through [Vercel AI Gateway](https://vercel.com/docs/ai-gateway), which is globally reachable and exposes an OpenAI-compatible endpoint that n8n's OpenAI Chat Model node can target natively.

---

## What this adapter does

This adapter bridges two things:

1. **AI-AO protocol** — receives task envelopes from NATS, publishes lifecycle events back
2. **n8n AI Agent** — the actual reasoning engine; an n8n workflow using the OpenAI Chat Model node pointed at Vercel AI Gateway, backed by `claude-opus-4.7`

```
┌──────────────┐   NATS          ┌──────────────────────────┐
│ Orchestrator │ ─────────────▶  │ adapter-n8n-claude-opus  │
└──────────────┘  task.assigned  │  (TypeScript)            │
       ▲                         │  • envelope → n8n payload│
       │                         │  • poll n8n exec API     │
       └──── NATS ───────────────│  • map result → event    │
              task events        └────────────┬─────────────┘
                                              │ POST /webhook/<id>
                                              ▼
                                 ┌────────────────────────────┐
                                 │  n8n AI Agent workflow     │
                                 │  ┌──────────────────────┐  │
                                 │  │ OpenAI Chat Model    │  │
                                 │  │ base_url:            │  │
                                 │  │  ai-gateway.vercel.sh│  │
                                 │  │ model:               │  │
                                 │  │  anthropic/claude-   │  │
                                 │  │  opus-4.7            │  │
                                 │  └──────────────────────┘  │
                                 │  + Tools (MCP, HTTP, etc.) │
                                 └────────────────────────────┘
                                              │
                                              ▼
                                 ┌────────────────────────────┐
                                 │  Vercel AI Gateway         │
                                 │  ai-gateway.vercel.sh      │
                                 │  (OpenAI-compatible API)   │
                                 └────────────────────────────┘
                                              │
                                              ▼
                                 ┌────────────────────────────┐
                                 │  Claude Opus 4.7           │
                                 │  (Anthropic via Vercel)    │
                                 └────────────────────────────┘
```

> For the canonical end-to-end notification flow see [`docs/AGENT-NOTIFICATION.md`](../../docs/AGENT-NOTIFICATION.md).

---

## Why n8n as the agent runtime

| Concern | How n8n solves it |
|---------|------------------|
| **Geo-restriction** | n8n calls Vercel AI Gateway (globally reachable); no direct `api.anthropic.com` calls |
| **Tool ecosystem** | n8n has 400+ native integrations (Notion, Slack, GitHub, Google Drive, HTTP…) usable as AI Agent tools out of the box |
| **Workflow orchestration** | Sub-agents, loops, conditional branches — no custom code |
| **Observability** | n8n execution logs complement AI-AO's OTel traces |
| **Fast iteration** | Workflows can be modified without adapter redeployment |

---

## Capabilities exposed

| Capability | Notes |
|------------|-------|
| `research` | Web search + synthesis via Claude Opus 4.7 + n8n HTTP tools |
| `reasoning` | Complex multi-step reasoning, planning, decomposition |
| `document-generation` | Reports, ADRs, runbooks produced as Markdown or structured doc |
| `code-review` | With codebase context passed via `context_refs` |
| `system-design` | Architecture analysis and recommendation |

---

## n8n Workflow Setup

### Step 1 — Vercel AI Gateway credential in n8n

In n8n → Settings → Credentials → Add Credential → **OpenAI**:

| Field | Value |
|-------|-------|
| **API Key** | Your Vercel AI Gateway API key |
| **Base URL** | `https://ai-gateway.vercel.sh/v1` |
| **Organization ID** | *(leave blank)* |

### Step 2 — AI Agent workflow

Create a workflow with a **Webhook trigger** (the adapter calls this) and attach:

- **AI Agent node** (Tools Agent)
  - Chat Model: **OpenAI Chat Model**
    - Model: `anthropic/claude-opus-4.7`
    - Credential: the one created in Step 1
    - ⚠️ **Disable the Responses API toggle** — Vercel gateway does not support the Responses API format for Anthropic models
  - Memory: **Window Buffer Memory** (session key = `task_id` from webhook payload)
  - Tools: add as needed (HTTP Request, GitHub, Notion, etc.)

### Step 3 — Webhook payload contract

The adapter POSTs this to n8n on task arrival:

```json
{
  "task_id": "01HXYZAB12CDEF34GHJK56MNPQ",
  "trace_id": "00f067aa0ba902b7",
  "goal": "Research best Southeast Asia destinations for October travel",
  "success_criteria": [
    "Cover at least 5 destinations",
    "Include weather, crowd levels, budget estimate"
  ],
  "deliverable_type": "markdown_report",
  "context_refs": [],
  "constraints": {
    "budget_usd": 1.00,
    "deadline": "2026-06-02T20:00:00+08:00",
    "autonomy_level": "supervised",
    "data_classification": "public"
  },
  "callback_url": "http://adapter-n8n-claude-opus:8204/webhook/complete"
}
```

n8n workflow responds with HTTP 200 immediately (ack), then calls `callback_url` on completion:

```json
{
  "task_id": "01HXYZAB12CDEF34GHJK56MNPQ",
  "status": "completed",
  "summary": "Research complete — 6 destinations covered.",
  "output": "# Southeast Asia Travel...",
  "cost_usd": 0.0312,
  "tokens": { "input": 2100, "output": 8400 }
}
```

### Step 4 — Fast mode (optional)

Opus 4.7 fast mode delivers up to 2.5× faster responses at higher token cost.
Enable it on the n8n worker environment:

```bash
CLAUDE_CODE_ENABLE_OPUS_4_7_FAST_MODE=1
CLAUDE_CODE_SKIP_FAST_MODE_ORG_CHECK=1
```

Or set `providerOptions: { anthropic: { speed: "fast" } }` in a custom Code node if using the Vercel AI SDK directly.

---

## Configuration

| Env var | Purpose | Default |
|---------|---------|---------|
| `ADAPTER_N8N_HTTP_PORT` | Adapter health + callback webhook port | `8204` |
| `ADAPTER_N8N_WORKFLOW_URL` | Full n8n webhook URL for the AI Agent workflow | *(required)* |
| `ADAPTER_N8N_API_KEY` | n8n API key (for execution status polling) | *(required)* |
| `ADAPTER_N8N_VERCEL_GATEWAY_KEY` | Vercel AI Gateway API key (injected into n8n credential) | *(required)* |
| `ADAPTER_N8N_MODEL` | Model identifier passed to the workflow | `anthropic/claude-opus-4.7` |
| `ADAPTER_N8N_MAX_CONCURRENT` | Max in-flight tasks | `3` |
| `ADAPTER_N8N_TIMEOUT_SECONDS` | Hard timeout before emitting `task.failed` | `1800` |

---

## Cost reporting

Each `completed` event emits:

```json
{
  "cost_usd": 0.0312,
  "tokens": { "input": 2100, "output": 8400 },
  "model": "anthropic/claude-opus-4.7",
  "gateway": "vercel-ai-gateway"
}
```

Token counts come from the n8n workflow's completion callback. The orchestrator's cost-aggregator writes these to Postgres.

---

## Deploy

```bash
# Start adapter only
docker compose --profile n8n-claude-opus up -d adapter-n8n-claude-opus

# Start with n8n self-hosted (optional — if you don't have a separate n8n instance)
docker compose --profile n8n-claude-opus --profile n8n up -d
```

---

## Implementation status

Phase 5 deliverable (alongside the Perplexity Computer adapter). The adapter is API-based; n8n is the hosted agent runtime.

---

## Relationship to other adapters

| Adapter | Model | Best for |
|---------|-------|---------|
| `perplexity-computer` | Perplexity Computer | Real-time web research, artifact generation |
| `n8n-claude-opus` | Claude Opus 4.7 (via Vercel) | Deep reasoning, planning, long-context tasks, workflow-integrated tools |
| `openclaw` | OpenClaw runtime | Deterministic, guideline-driven execution (native NATS) |
| `manus` | Manus | UI-only platforms (browser automation) |
