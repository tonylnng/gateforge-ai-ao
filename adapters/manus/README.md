# Adapter — Manus (Browser-based via Playwright)

> **Class:** Browser · **Status:** Reference adapter · **Language:** TypeScript (Node + Playwright)

Manus is a UI-only agent (no public API at time of writing). To integrate it deterministically, we run a headed Chromium under Playwright with a long-lived authenticated session.

## ⚠️ Read before deploying

Browser-based adapters are **the most fragile** of the three classes:

- The session cookie expires (~ weekly); see [/install/runbooks/browser-session-refresh.md](../../install/runbooks/browser-session-refresh.md).
- UI changes can break selectors. Tests must run nightly.
- Compute-hungry: a Chromium process per concurrent task.

Use this adapter only when no API is available.

## Capabilities exposed

| Capability       | Notes                                          |
| ---------------- | ---------------------------------------------- |
| `code-review`    | Manus's coding agent flow                      |
| `research`       | When the API-based adapter is unavailable      |

## Architecture

```
┌─────────────┐  NATS   ┌────────────────────────┐
│ Orchestrator│────────▶│ adapter-manus (TS)     │
└─────────────┘         │  ┌──────────────────┐  │
       ▲                │  │ Playwright pool  │──┼──▶ manus.im (UI)
       │                │  │  • headless      │  │
       │                │  │  • session reuse │  │
       └─── NATS ───────│  │  • DOM events    │  │
                        │  └──────────────────┘  │
                        │  • output extraction   │
                        │  • screenshot to S3    │
                        └────────────────────────┘
```

## Configuration

| Env var                       | Purpose                                           |
| ----------------------------- | ------------------------------------------------- |
| `ADAPTER_MANUS_BASE_URL`      | Defaults to `https://manus.im`                    |
| `ADAPTER_MANUS_SESSION_PATH`  | Path to Playwright `storageState` JSON            |
| `ADAPTER_MANUS_HTTP_PORT`     | Health + control port (default 8202)              |

## Session bootstrap (one-time, manual)

1. Run `playwright install chromium` on a desktop.
2. `npx playwright codegen --save-storage=manus-session.json https://manus.im`
3. Log in interactively, accept any 2FA, then close the window.
4. Copy `manus-session.json` to `infrastructure/secrets/manus-session.json`.
5. Update `.env` with the path.

Refresh runbook: [browser-session-refresh.md](../../install/runbooks/browser-session-refresh.md).

## Deploy

```bash
docker compose --profile manus up -d adapter-manus
```

## Implementation status

Phase 5 deliverable. Conformance suite includes a session-expiry probe.
