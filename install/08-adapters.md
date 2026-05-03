# 08 — Adapters

Adapters are how AI-AO talks to specific agent platforms. One per platform.

---

## Adapter classes

| Class | Example | Reach |
|-------|---------|-------|
| **Native** | OpenClaw | Speaks AI-AO SDK directly via NATS |
| **API-based** | Perplexity Computer (where API exists) | Calls platform HTTPS API |
| **Browser-based** | Manus, ChatGPT Agent | Drives browser via Playwright |

All three present the same shape to the bus. Asymmetry is hidden inside.

---

## Lifecycle

```
1. Container starts
2. Reads config from env (NATS URL, platform credentials, agent_id)
3. Publishes its agent card to NATS KV `agents.<agent_id>`
4. Starts heartbeat goroutine (every 10s)
5. Subscribes to its inbound subject (`project.*.task.*.assigned` filtered to its capabilities)
6. On message: validate envelope, ack within 1s, invoke platform, stream progress, publish completion
7. On shutdown: publish tombstone, drain in-flight tasks, exit
```

---

## Reference adapters in this repo

| Folder | Type | Status |
|--------|------|--------|
| `adapters/_scaffold/` | Template + echo adapter | Phase 0: scaffold ready |
| `adapters/openclaw/` | Native | Phase 4 |
| `adapters/perplexity-computer/` | API-based | Phase 5 |
| `adapters/manus/` | Browser-based | Phase 7 |

---

## Container pattern

Every adapter follows the same Docker pattern:

```yaml
# infrastructure/docker-compose.yml (excerpt)
adapter-perplexity-computer:
  build:
    context: ../adapters/perplexity-computer
  image: ai-ao/adapter-perplexity-computer:0.1.0
  container_name: ai-ao-adapter-perplexity-computer
  restart: unless-stopped
  profiles: [perplexity]    # opt-in
  depends_on:
    nats: { condition: service_healthy }
  environment:
    OTEL_SERVICE_NAME: adapter-perplexity-computer
    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
    NATS_URL: nats://nats:4222
    NATS_USER: ${NATS_BOOTSTRAP_USER}
    NATS_PASSWORD: ${NATS_BOOTSTRAP_PASSWORD}
    AGENT_ID: perplexity-computer-prod
    PERPLEXITY_API_KEY: ${PERPLEXITY_API_KEY}
    MINIO_ENDPOINT: minio:9000
    MINIO_ACCESS_KEY: ${MINIO_ROOT_USER}
    MINIO_SECRET_KEY: ${MINIO_ROOT_PASSWORD}
    MAX_CONCURRENT: 3
  healthcheck:
    test: ["CMD-SHELL", "wget -qO- http://localhost:8090/health | grep -q ok"]
    interval: 10s
    timeout: 3s
    retries: 5
```

The `profiles` key means the adapter only starts when you opt in:

```bash
docker compose --profile perplexity up -d
```

To always-start an adapter, remove `profiles`.

---

## Echo adapter (for testing)

`adapters/_scaffold/` ships with a working **echo adapter** that:

- Advertises capability `echo`
- On any task, immediately publishes `task.accepted`
- Then publishes `task.completed` with `data.summary = "echo: <goal>"`
- Costs $0
- Useful for verifying the orchestrator and bus end-to-end without any real platform

Run it:

```bash
docker compose up -d adapter-echo
```

Then file a GitHub issue with label `capability:echo` on a connected project repo. Watch the round-trip.

---

## Writing a new adapter

See [`adapters/_scaffold/README.md`](../adapters/_scaffold/README.md) for the full walkthrough. Quick summary:

1. Copy `adapters/_scaffold/` to `adapters/<your-platform>/`
2. Implement the `Translate` and `Invoke` methods (Go) or `translate()` / `invoke()` (TypeScript)
3. Update the agent card in `agent-card.yaml` (capabilities, cost, rate limits)
4. Add the service to `infrastructure/docker-compose.yml` under a new profile
5. Add platform credentials to `infrastructure/.env.example`
6. Run `tools/conformance-test/ ./adapters/<your-platform>/` — must pass
7. Open PR

The conformance suite covers: schema validation, idempotency, ack SLA, error taxonomy, OTel propagation.

---

## Closed-platform adapters

Closed platforms (Perplexity Computer, Manus, ChatGPT Agent) cannot host webhook servers. The adapter pattern handles this:

- The **adapter** runs on **your VM**
- It speaks NATS directly to the AI-AO bus
- It calls the platform's API (or drives its UI via browser automation)
- The platform itself never sees AI-AO's webhook surface

For browser-based adapters, the recommended approach:

```yaml
# adapter container also runs Playwright + Chromium
adapter-manus:
  build:
    context: ../adapters/manus
  # Image is larger (~600 MB) due to Chromium
  shm_size: 1gb           # Chromium needs shared memory
  environment:
    MANUS_LOGIN_EMAIL: ${MANUS_LOGIN_EMAIL}
    MANUS_LOGIN_SESSION_PATH: /run/secrets/manus-session
  secrets:
    - manus-session
  volumes:
    - manus-screenshots:/var/lib/manus/screenshots
```

Browser-based adapters store login session state in a Docker secret so they don't need to log in fresh each time.

---

## Per-adapter scaling

```bash
# Scale an adapter horizontally (NATS consumer group distributes work)
docker compose up -d --scale adapter-perplexity-computer=3
```

Set `MAX_CONCURRENT` per instance based on the platform's rate limits and the number of instances.

---

## Verification

```bash
# Adapter is heartbeating
nats kv get agents perplexity-computer-prod
# returns the latest agent card

# Adapter responds to a synthetic task
nats pub project.test-project.task.test-task-id.assigned \
  --reply project.test-project.task.test-task-id.accepted \
  '{"envelope_version":"1.0","task_id":"...","capability_required":"research",...}'
# Should receive task.accepted event within 1s
```

A more thorough check is the smoke test: `tools/smoke-test.sh`.

---

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Adapter not in registry | NATS KV write failed at startup | Check NATS auth + adapter logs |
| `task.assigned` not received | Subject filter wrong, or wrong consumer group | Check adapter logs for subscribe errors |
| Browser adapter timing out | Session expired | Re-authenticate; check `runbooks/browser-session-refresh.md` |
| Adapter holding > MAX_CONCURRENT | Concurrency cap not enforced | Check adapter source — semaphore around invoke |
