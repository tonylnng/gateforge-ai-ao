# Runbook — Troubleshooting

> First stop when the stack misbehaves. Symptoms → likely cause → action.

## Quick triage commands

```bash
docker compose ps                          # all should be "healthy"
docker compose logs -f orchestrator        # most informative log
nats stream report --server=nats://localhost:4222
mc admin info local                        # MinIO health
psql "$POSTGRES_DSN" -c "SELECT now();"    # PG reachable?
curl -s localhost:8080/healthz             # orchestrator health
curl -s localhost:8080/readyz              # orchestrator ready (deps OK)
```

## Symptom matrix

| Symptom                                                          | Likely cause                                          | Action                                                                                  |
| ---------------------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `orchestrator` container restarts every 30s                      | Cannot reach NATS/PG/MinIO                            | `docker compose logs orchestrator` → fix env or wait for dependency healthcheck         |
| Tasks accepted but never reach `started`                         | No adapter subscribed to capability                   | `nats consumer report TASKS` — check delivery; verify adapter container is running       |
| Tasks stuck in `running` past `timeout_seconds`                  | Adapter died without emitting `failed`                 | Watchdog should auto-fail in ≤ 60s; if not, check `aiao_watchdog_*` metrics              |
| Cost rollups not updating                                        | `cost-aggregator` consumer offline                    | Restart orchestrator; consumer offsets are durable so no data lost                      |
| Admin Portal shows stale state                                   | SSE connection dropped                                 | See [Admin Portal Upgrade](../../docs/ADMIN-PORTAL-UPGRADE.md) — should subscribe to NATS directly |
| `policy.yaml` change not taking effect                           | Hot-reload SIGHUP not delivered                       | `docker compose kill -s HUP orchestrator`                                                |
| MinIO refusing PUT — `XAmzContentSHA256Mismatch`                 | Clock drift between adapter and MinIO                 | `timedatectl` on host; restart container                                                |
| NATS stream rejects publish — `maximum messages exceeded`        | Stream limit reached; lifecycle not pruning           | Bump `max_msgs`/`max_bytes` in `jetstream-streams.yaml`, re-apply                        |
| GitHub webhook returns 401                                       | HMAC mismatch — secret rotated                        | See [secret-rotation.md](secret-rotation.md)                                             |
| Manus adapter fails with `selector not found`                    | UI changed OR session expired                         | See [browser-session-refresh.md](browser-session-refresh.md)                              |

## When in doubt

1. Open Grafana → **AI-AO — Overview** dashboard.
2. Pivot to **Task Explorer** with the failing task ID.
3. Logs and traces will be cross-linked.

## Escalation

Open an issue using the **Bug Report** template in `.github/ISSUE_TEMPLATE/`.
