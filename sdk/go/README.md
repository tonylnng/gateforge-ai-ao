# GateForge AI-AO — Go SDK (`aiao-go`)

> **Status:** Scaffold (Phase 4 deliverable). Reference implementation lives here once Phase 4 is built.

The Go SDK is the canonical reference because the orchestrator is also written in Go. Anything the SDK can do, the orchestrator can verify behaviorally.

```text
sdk/go/
├── client/                 NATS + HTTP client — connect, publish, subscribe
├── envelope/               Task envelope marshal/validate (uses /protocol/schema)
├── adapter/                Helpers for building adapters (heartbeat, claim/ack)
├── policy/                 Local policy evaluation helpers (read-only)
└── examples/
    ├── minimal-publisher/
    ├── minimal-adapter/
    └── audit-tail/
```

## Install (once published)

```bash
go get github.com/tonylnng/gateforge-ai-ao/sdk/go@v0.1.0
```

## What you get

| Package         | Purpose                                                    |
| --------------- | ---------------------------------------------------------- |
| `client`        | One-line connect to NATS+JetStream, JWT/seed auth helpers  |
| `envelope`      | Strongly-typed task envelope, schema-validated on build    |
| `adapter`       | `Run(handlerFn)` loop with claim → execute → ack           |
| `policy`        | Optional client-side gate before publish (cost preview)    |

## Versioning

The SDK tracks the **protocol version** (see `/protocol/version.txt`).
SDK `v0.1.x` ⇒ Protocol `1.0.0-draft`. SemVer rules in [/CONTRIBUTING.md](../../CONTRIBUTING.md).

## Hello-world adapter (preview)

```go
package main

import (
    "context"
    aiao "github.com/tonylnng/gateforge-ai-ao/sdk/go/adapter"
)

func main() {
    a, _ := aiao.New(aiao.Config{
        AgentID:      "hello/v1",
        Capabilities: []string{"echo"},
        NATSURL:      "nats://nats:4222",
    })
    a.OnTask("echo", func(ctx context.Context, t *aiao.Task) (*aiao.Result, error) {
        return &aiao.Result{Output: t.Input}, nil
    })
    a.Run()
}
```

## Roadmap

- **Phase 4** — `client`, `envelope`, `adapter` core
- **Phase 5** — policy preview, OTel auto-instrumentation
- **Phase 6** — chaos & contract test harness for adapter authors
