# 02 — Quickstart

Bring the full AI-AO stack up on a single VM in under 10 minutes.

This is the **fast path**. Detail per component is in `03-nats.md` through `10-security.md`. After this guide, run [`11-verification.md`](11-verification.md) to confirm everything works.

---

## Step 1: Clone the repo

```bash
cd /opt
sudo git clone https://github.com/tonylnng/gateforge-ai-ao.git
sudo chown -R $USER:$USER /opt/gateforge-ai-ao
cd /opt/gateforge-ai-ao
```

---

## Step 2: Generate secrets and configure environment

```bash
cd /opt/gateforge-ai-ao/infrastructure

# Copy the template
cp .env.example .env

# Generate strong random values for secrets
chmod +x ./scripts/generate-secrets.sh
./scripts/generate-secrets.sh > .env.secrets

# Combine
cat .env.secrets >> .env
rm .env.secrets

# Open .env and review. Set:
#   - PUBLIC_HOST (your VM's hostname or 'localhost' for dev)
#   - GH_APP_ID, GH_APP_PRIVATE_KEY_PATH (after Step 6)
${EDITOR:-vi} .env
```

The default `.env.example` includes safe-but-replace defaults for everything except secrets and your GitHub App credentials. Secrets are auto-generated; GitHub App config you'll fill in at Step 6.

**Required variables (must be set before bringing up):**

```bash
PUBLIC_HOST=localhost                    # or your real hostname for prod
NATS_JETSTREAM_DOMAIN=ai-ao
MINIO_ROOT_USER=ai-ao-admin
MINIO_ROOT_PASSWORD=<generated>
POSTGRES_PASSWORD=<generated>
GRAFANA_ADMIN_PASSWORD=<generated>
ORCH_HMAC_SECRET=<generated>
ORCH_JWT_SIGNING_KEY=<generated>
```

---

## Step 3: Pull images

```bash
cd /opt/gateforge-ai-ao/infrastructure
docker compose pull
```

This downloads all pinned images (~2 GB total). Takes 1–3 minutes on a decent connection.

---

## Step 4: Bring the substrate up (NATS + MinIO + Postgres + Observability)

```bash
docker compose up -d nats minio postgres otel-collector tempo loki grafana

# Wait for health checks (about 30 seconds)
docker compose ps
```

All services should show `healthy`. If any are `unhealthy`, see [`runbooks/troubleshooting.md`](runbooks/troubleshooting.md).

### Verify NATS is up

```bash
curl -s http://localhost:8222/healthz
# {"status":"ok"}

curl -s http://localhost:8222/jsz | jq '.streams'
# Should show TASKS, AGENTS, REGISTRY, AUDIT, DLQ pre-created
```

### Verify MinIO is up

```bash
curl -s http://localhost:9000/minio/health/live
# 200 OK

# Browse: http://<your-host>:9001  (login with MINIO_ROOT_USER / MINIO_ROOT_PASSWORD)
```

### Verify Postgres is up

```bash
docker compose exec postgres pg_isready -U ai_ao
# postgres:5432 - accepting connections
```

### Verify Grafana is up

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000
# 302 (redirect to login)

# Browse: http://<your-host>:3000  (login: admin / GRAFANA_ADMIN_PASSWORD)
# Pre-loaded dashboards should appear under "AI-AO" folder
```

---

## Step 5: Initialize streams, buckets, and database schemas

```bash
# All idempotent. Safe to re-run.
docker compose run --rm init-nats
docker compose run --rm init-minio
docker compose run --rm init-postgres
```

Each init container reads from `infrastructure/<component>/` configs and creates streams, buckets, and tables as needed.

---

## Step 6: Set up the GitHub App

Follow [`09-github-app.md`](09-github-app.md). Quick summary:

1. Create a GitHub App in your account/org
2. Set webhook URL to `https://<PUBLIC_HOST>/v1/webhooks/github`
3. Set webhook secret to value of `GITHUB_WEBHOOK_SECRET` from your `.env`
4. Grant permissions: Contents (read/write), Issues (read/write), Pull requests (read/write), Metadata (read), Webhooks (write on receiving)
5. Subscribe to events: Issues, Issue comments, Push, Pull request, Pull request review
6. Generate and download the private key, save to `/opt/secrets/ai-ao-gh-app.pem`
7. Note the App ID; set `GH_APP_ID` in `.env` and `GH_APP_PRIVATE_KEY_PATH=/opt/secrets/ai-ao-gh-app.pem`
8. Install the App on the project repos AI-AO will manage

---

## Step 7: Bring the orchestrator up

```bash
cd /opt/gateforge-ai-ao/infrastructure
docker compose up -d orchestrator

# Verify
curl -s http://localhost:8080/v1/health | jq
# {"status":"ok","version":"0.1.0","protocol_version":"1.0"}
```

---

## Step 8: Bring at least one adapter up

The repo ships reference adapters under `adapters/`. The simplest to start with is the OpenClaw adapter (if you have OpenClaw VMs) or the `_scaffold` echo adapter for testing.

```bash
# For testing: an echo adapter that pretends to be an agent
docker compose up -d adapter-echo

# Or, if you have OpenClaw VMs configured in .env:
docker compose --profile openclaw up -d adapter-openclaw

# Or, with Perplexity API key set in .env:
docker compose --profile perplexity up -d adapter-perplexity-computer
```

Profiles let you opt into specific adapters. `infrastructure/.env.example` lists every adapter and the env vars each requires.

---

## Step 9: Verify end-to-end

Run the smoke test:

```bash
cd /opt/gateforge-ai-ao
./tools/smoke-test.sh
```

Expected output:

```
[ok] NATS reachable
[ok] MinIO reachable, buckets initialized
[ok] Postgres reachable, schemas migrated
[ok] Orchestrator healthy
[ok] At least one adapter heartbeating: adapter-echo
[ok] Test task assigned, accepted, completed in 1.4s
[ok] Artifact written to MinIO and referenced in Git (dry-run)
[ok] Trace visible in Grafana Tempo

Smoke test PASSED.
```

If any line fails, the script tells you which step to inspect.

For full verification including chaos and load tests, see [`11-verification.md`](11-verification.md).

---

## What's running now

```
$ docker compose ps
NAME                IMAGE                                                    STATUS
ai-ao-nats          nats:2.10.20-alpine                                      Up (healthy)
ai-ao-minio         minio/minio:RELEASE.2025-01-20T14-49-07Z                 Up (healthy)
ai-ao-postgres      postgres:16.6-alpine                                     Up (healthy)
ai-ao-otel          otel/opentelemetry-collector-contrib:0.115.0             Up (healthy)
ai-ao-tempo         grafana/tempo:2.6.1                                      Up (healthy)
ai-ao-loki          grafana/loki:3.3.2                                       Up (healthy)
ai-ao-grafana       grafana/grafana:11.4.0                                   Up (healthy)
ai-ao-orchestrator  ai-ao/orchestrator:0.1.0                                 Up (healthy)
ai-ao-adapter-echo  ai-ao/adapter-echo:0.1.0                                 Up (healthy)
```

---

## Stopping the stack

```bash
docker compose down                # stop containers, keep volumes
docker compose down -v             # stop containers AND delete all data (destructive)
```

Use the second form only when you want a fresh state.

---

## Next steps

- [`11-verification.md`](11-verification.md) — full smoke + chaos tests
- [`07-orchestrator.md`](07-orchestrator.md) — orchestrator deep-dive
- [`08-adapters.md`](08-adapters.md) — write or deploy more adapters
- [`10-security.md`](10-security.md) — harden for production

---

## When something goes wrong

Always start here:

```bash
# Health of every container
docker compose ps

# Logs of a specific container
docker compose logs -f <name>

# Inspect NATS streams
docker compose exec nats nats stream ls

# Inspect MinIO buckets
docker compose exec minio mc ls local/
```

Detailed troubleshooting in [`runbooks/troubleshooting.md`](runbooks/troubleshooting.md).
