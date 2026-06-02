# ADR-0004: n8n + Vercel AI Gateway as the Claude Opus 4.7 adapter pattern

- **Status:** Accepted
- **Date:** 2026-06-02
- **Deciders:** Tony Lnng

## Context

Claude Opus 4.7 is the highest-capability reasoning model available and is the intended "Brains" component for complex AI-AO tasks (system-design, deep reasoning, long-context document generation, code review).

However, two constraints apply in this deployment:

1. **Geo-restriction:** Anthropic's direct API (`api.anthropic.com`) is blocked / restricted from Hong Kong. Adapters running on HK-based VMs cannot call it directly.

2. **Tool ecosystem:** The orchestrator needs an agent that can use external tools (Notion, GitHub, Google Drive, Slack, HTTP endpoints) as part of task execution — not just raw LLM inference.

## Decision

Use **n8n as the agent runtime** for Claude Opus 4.7, with the following stack:

```
AI-AO Adapter (TypeScript)
  → n8n AI Agent workflow (Tools Agent)
      → OpenAI Chat Model node
          → Vercel AI Gateway (ai-gateway.vercel.sh)
              → Claude Opus 4.7
```

Key choices:

- **Vercel AI Gateway** as the API proxy. It exposes an OpenAI-compatible endpoint (`/v1`) that is globally reachable (no geo-restriction), accepts the model identifier `anthropic/claude-opus-4.7`, and handles authentication, retries, and failover transparently.
- **n8n OpenAI Chat Model node** (not the Anthropic node) as the model connector. The Anthropic node in n8n hardcodes `api.anthropic.com` and does not support custom base URLs. The OpenAI node accepts a configurable Base URL, making it the correct vehicle for pointing at a compatible gateway.
- **Responses API disabled** in the n8n OpenAI Chat Model node. Vercel AI Gateway does not support the Responses API format for non-OpenAI models. Standard Chat Completions format is used instead.
- **n8n AI Agent (Tools Agent)** as the agentic loop. This gives Claude access to n8n's 400+ integrations as tools without building custom tool-calling infrastructure in the adapter.

## Consequences

**Easier:**
- No VPN or proxy required on the VM — Vercel's edge handles the geo-routing
- n8n's tool ecosystem is immediately available to Claude without additional integration work
- Fast mode (`anthropic/claude-opus-4.7` with `speed: "fast"`) is available when needed, providing up to 2.5× faster responses
- n8n workflows can be updated without adapter redeployment
- Execution logs in n8n provide a second observability layer alongside AI-AO's OTel traces
- The adapter pattern is identical to `perplexity-computer` (API-based class) — same NATS lifecycle, same envelope/event model

**Harder:**
- Two systems to operate (AI-AO adapter + n8n)
- Cost visibility is split: Vercel AI Gateway reports token cost; n8n reports execution time. AI-AO's cost aggregator reconciles via the adapter's completion callback.
- `confidential` and `restricted` data classifications must NOT be routed through this adapter — data transits Vercel's cloud. Only `public` and `internal` classifications are accepted.
- Session state in n8n (Window Buffer Memory) is keyed by `task_id` — long-running tasks that exceed n8n's memory window need chunking at the adapter level.

## Alternatives considered

- **Direct Anthropic API with VPN on the VM:** rejected. VPN is operational complexity; adds latency; fragile for automated, headless agent workloads.
- **AWS Bedrock (Claude via Bedrock):** viable alternative but requires AWS account, IAM setup, and Bedrock-specific inference profile ARNs. Adds cloud provider dependency. Deferred to a future adapter (`adapters/bedrock-claude/`).
- **n8n Anthropic node with forked base URL:** rejected. Forking n8n to patch `api.anthropic.com` creates a maintenance burden on every n8n upgrade.
- **LiteLLM proxy self-hosted:** viable but adds another service to the stack. Vercel AI Gateway achieves the same without self-hosting.
- **Vercel AI SDK community node for n8n:** promising but requires self-hosted n8n and introduces a community node dependency. The OpenAI node approach uses only official n8n nodes.

## References

- [`adapters/n8n-claude-opus/README.md`](../../adapters/n8n-claude-opus/README.md)
- [`adapters/n8n-claude-opus/agent-card.yaml`](../../adapters/n8n-claude-opus/agent-card.yaml)
- [Vercel AI Gateway — Claude Opus 4.7](https://vercel.com/ai-gateway/models/claude-opus-4.7)
- [Vercel AI Gateway — Claude Code setup](https://vercel.com/docs/ai-gateway/coding-agents/claude-code)
- [n8n OpenAI Chat Model node](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.lmchatopenai/)
