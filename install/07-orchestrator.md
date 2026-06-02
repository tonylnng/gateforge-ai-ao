# 07 — Orchestrator

The "prime AI" router service. Receives webhooks, routes by capability, watches lifecycle, mirrors to Git.

---

## What it does

```mermaid
flowchart LR
    GH["GitHub webhook"]
    ORCH["Orchestrator"]
    NATS_SVC["NATS subject"]
    ADP["Adapter"]
    PLAT["Platform"]

    GH --> ORCH --> NATS_SVC --> ADP --> PLAT

    ORCH -->|NATS KV| KV["registry, seen, task_state"]
    ORCH -->|Postgres| PG["cost, audit aggregates, breakers"]
    ORCH -->|Git| GIT["commits, issue updates"]
    ORCH -->|OTel| OTEL["traces, metrics, logs"]
```

Stateless. Restart anytime. Pluggable.

---

## Container

Built from `orchestrator/`. The repo includes a Dockerfile that produces a ~30 MB Go binary image.

```yaml
# infrastructure/docker-compose.yml (excerpt)
orchestrator:
  build:
    context: ../orchestrator
  image: ai-ao/orchestrator:0.1.0
  container_name: ai-ao-orchestrator
  restart: unless-stopped
  depends_on:
    nats: { condition: service_healthy }
    postgres: { condition: service_healthy }
    minio: { condition: service_healthy }
  ports:
    - "8080:8080"
  environment:
    OTEL_SERVICE_NAME: orchestrator
    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
    NATS_URL: nats://nats:4222
    NATS_USER: ${NATS_BOOTSTRAP_USER}
    NATS_PASSWORD: ${NATS_BOOTSTRAP_PASSWORD}
    POSTGRES_URL: postgres://ai_ao:${POSTGRES_PASSWORD}@postgres:5432/ai_ao
    MINIO_ENDPOINT: minio:9000
    MINIO_ACCESS_KEY: ${MINIO_ROOT_USER}
    MINIO_SECRET_KEY: ${MINIO_ROOT_PASSWORD}
    GH_APP_ID: ${GH_APP_ID}
    GH_APP_PRIVATE_KEY_PATH: /run/secrets/gh-app-key
    GITHUB_WEBHOOK_SECRET: ${GITHUB_WEBHOOK_SECRET}
    HMAC_SECRET: ${ORCH_HMAC_SECRET}
    JWT_SIGNING_KEY: ${ORCH_JWT_SIGNING_KEY}
    PUBLIC_HOST: ${PUBLIC_HOST}
  secrets:
    - gh-app-key
  healthcheck:
    test: ["CMD-SHELL", "wget -qO- http://localhost:8080/v1/health | grep -q ok"]
    interval: 10s
    timeout: 3s
    retries: 5

secrets:
  gh-app-key:
    file: /opt/secrets/ai-ao-gh-app.pem
```

---

## HTTP endpoints

| Path | Purpose |
|------|---------|
| `GET /v1/health` | Liveness/readiness |
| `POST /v1/webhooks/github` | GitHub webhook receiver |
| `POST /v1/tasks` | Create task (programmatic; for Admin Portal) |
| `POST /v1/tasks/:id/control` | Cancel/redirect/approve a task |
| `GET /v1/tasks/:id` | Read task state (returns latest from NATS KV) |
| `GET /v1/agents` | List registered agents |
| `POST /v1/auth/rotate` | Rotate adapter JWT |
| `GET /v1/metrics` | Prometheus scrape endpoint |
| `POST /v1/ingest` | Webhook fallback for adapters that can't speak NATS |

All endpoints (except `/v1/health` and `/v1/metrics`) require auth — JWT for adapters, GitHub HMAC signature for `/v1/webhooks/github`, operator JWT for `/v1/tasks` and `/v1/tasks/:id/control`.

---

## Routing logic (simplified)

```go
// pseudocode
func RouteTask(envelope Task) {
    candidates := registry.AgentsFor(envelope.CapabilityRequired)
    candidates = filter(candidates, by acceptsDataClass(envelope.DataClassification))
    candidates = filter(candidates, by hasCapacity())
    candidates = filter(candidates, by circuitBreakerClosed())
    candidates = filter(candidates, by withinBudget(envelope.BudgetUsd))

    chosen := pickByPolicy(candidates)
        // policy: prefer lowest cost agent meeting reliability SLA
        //         fall back to next best on rejection

    nats.Publish("project.<proj>.task.<id>.assigned", envelope, headers={
        "traceparent": currentTraceContext(),
        "ai_ao.task_id": envelope.TaskID,
    })

    // Wait for ack with 1s SLA
    select {
        case ev := <-acks: handleAck(ev)
        case <-time.After(1 * time.Second): markStale(chosen); reroute(envelope)
    }
}
```

Full implementation in `orchestrator/internal/router/`.

---

## Reconciliation loop

Runs every 60s in a goroutine.

```
1. Read all open tasks from NATS KV `task_state`
2. For each, compare to corresponding tasks/open/<id>.md in Git
3. If Git has a newer state (e.g. human commented), publish a synthetic event
4. If NATS has a newer state, commit it to Git
5. If a task has been "assigned" but no "accepted" for > 5 min, reroute
```

Belt-and-suspenders against missed webhooks and adapter crashes.

---

## Configuration files

| Path | Purpose |
|------|---------|
| `infrastructure/policy/policy.example.yaml` | Default policy (budget, autonomy, breakers) |
| `orchestrator/config.example.yaml` | Routing weights, SLA tunables |

Both can be overridden per-project via the project repo's `.gateforge/policy.yaml`.

---

## Logs and traces to look for

```
# Successful task flow
INFO  task.received       project=p task_id=01H... capability=research
INFO  task.routed         project=p task_id=01H... agent=perplexity-computer-prod
INFO  task.published      subject=project.p.task.01H....assigned
INFO  task.accepted       agent=perplexity-computer-prod eta_seconds=120
INFO  task.completed      duration_ms=87234 cost_usd=0.34

# Routing failures
WARN  task.no_candidates  capability=code-review reason="all agents at capacity"
WARN  task.budget_exceeded project=p current_spend=100.50 cap=100.00
ERROR task.broker_error   error="JetStream publish failed"
```

In Tempo, the orchestrator span chain looks like:

```
orchestrator: webhook.received
  └─ orchestrator: task.route
       ├─ registry.lookup
       └─ orchestrator: task.publish
            └─ adapter: task.received   ← span continues in adapter service
```

---

## Verification

```bash
# Healthy
curl -s http://localhost:8080/v1/health | jq
# {"status":"ok","version":"0.1.0","protocol_version":"1.0"}

# Metrics
curl -s http://localhost:8080/v1/metrics | head
# # HELP ai_ao_tasks_total Total tasks routed by orchestrator
# # TYPE ai_ao_tasks_total counter
# ai_ao_tasks_total{result="completed"} 0

# Test webhook (with real GitHub HMAC; or use a tunnel like smee.io)
# Or: send a synthetic webhook
curl -X POST http://localhost:8080/v1/webhooks/github \
  -H "X-GitHub-Event: ping" \
  -H "X-Hub-Signature-256: sha256=..." \
  -H "Content-Type: application/json" \
  -d '{"zen":"Approachable","hook_id":1}'
```

---

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `unauthorized` on webhook | HMAC mismatch | Confirm `GITHUB_WEBHOOK_SECRET` matches GitHub App config |
| `no candidates` for valid task | Registry empty (no adapters running) | Check adapters are heartbeating |
| Tasks stuck in `assigned` | Adapter crashed without acking; reconciliation will reroute | Wait 5 min, or restart adapter |
| 500 from `/v1/tasks` | Postgres unreachable | `docker compose logs postgres` |
