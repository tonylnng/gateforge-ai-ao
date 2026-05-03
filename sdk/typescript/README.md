# GateForge AI-AO — TypeScript SDK (`@aiao/sdk`)

> **Status:** Scaffold (Phase 4 deliverable).

The TypeScript SDK targets two audiences:

1. **Adapter authors** building API-based adapters (e.g., the Perplexity Computer adapter is TS).
2. **Admin Portal & dashboards** that need to subscribe to live events from a browser/Node.

```
sdk/typescript/
├── packages/
│   ├── client/             nats.ws + REST helpers (browser-safe)
│   ├── envelope/           Zod-typed envelope from /protocol/schema
│   ├── adapter/            Node-only adapter runtime
│   └── react-events/       React hooks: useTaskStream, useAgentRoster
└── examples/
    ├── minimal-adapter-node/
    └── live-portal-react/
```

## Install (once published)

```bash
npm i @aiao/client @aiao/envelope        # browser + node
npm i @aiao/adapter                      # node only
npm i @aiao/react-events                 # react integration
```

## Hello-world adapter (preview)

```ts
import { Adapter } from "@aiao/adapter";

const a = new Adapter({
  agentId: "hello/v1",
  capabilities: ["echo"],
  natsUrl: "nats://nats:4222",
});

a.onTask("echo", async (task) => ({ output: task.input }));
await a.run();
```

## Browser subscription (for the upgraded Admin Portal)

```ts
import { createClient } from "@aiao/client";

const c = createClient({ wsUrl: "wss://aiao.example.com/nats" });
const stream = c.subscribe("aiao.event.>");
for await (const e of stream) console.log(e.subject, e.payload);
```

See `docs/ADMIN-PORTAL-UPGRADE.md` for how this replaces the current SQLite-backed read model.

## Roadmap

Mirrors the Go SDK roadmap, on the same phase cadence.
