# 05 — Postgres

Cost aggregation, long-term audit, and operational reporting.

**Important:** Postgres is **not** the system of record. Git is. Postgres holds queries Git can't answer efficiently — "total spend last 30 days, grouped by project and agent," etc.

---

## What's deployed

A single `postgres:16.6-alpine` container with persistent storage on port 5432.

---

## Container

```yaml
# infrastructure/docker-compose.yml (excerpt)
postgres:
  image: postgres:16.6-alpine
  container_name: ai-ao-postgres
  restart: unless-stopped
  environment:
    POSTGRES_USER: ai_ao
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    POSTGRES_DB: ai_ao
  volumes:
    - postgres-data:/var/lib/postgresql/data
    - ./postgres/init:/docker-entrypoint-initdb.d:ro
  ports:
    - "5432:5432"
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U ai_ao"]
    interval: 10s
    timeout: 3s
    retries: 5
```

`infrastructure/postgres/init/` contains migration SQL run on first start.

---

## Schema

Migrations live in `infrastructure/postgres/migrations/`.

```sql
-- 0001_init.sql

CREATE TABLE cost_events (
    id              BIGSERIAL PRIMARY KEY,
    occurred_at     TIMESTAMPTZ NOT NULL,
    task_id         TEXT NOT NULL,
    parent_task_id  TEXT,
    project         TEXT NOT NULL,
    agent_id        TEXT NOT NULL,
    vendor          TEXT NOT NULL,
    tokens_input    INTEGER NOT NULL DEFAULT 0,
    tokens_output   INTEGER NOT NULL DEFAULT 0,
    usd             NUMERIC(12,6) NOT NULL DEFAULT 0,
    billing_ref     TEXT,
    raw_event_id    TEXT NOT NULL,
    UNIQUE (raw_event_id)
);
CREATE INDEX idx_cost_events_project_day ON cost_events (project, date_trunc('day', occurred_at));
CREATE INDEX idx_cost_events_agent_day   ON cost_events (agent_id, date_trunc('day', occurred_at));
CREATE INDEX idx_cost_events_task        ON cost_events (task_id);

CREATE TABLE audit_aggregates (
    id              BIGSERIAL PRIMARY KEY,
    bucket          TEXT NOT NULL,         -- e.g. 'project_day_status'
    bucket_key      JSONB NOT NULL,        -- e.g. {"project":"x","day":"2026-05-03","status":"completed"}
    count           BIGINT NOT NULL,
    last_updated    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (bucket, bucket_key)
);
CREATE INDEX idx_audit_aggregates_bucket ON audit_aggregates (bucket);

CREATE TABLE policy_state (
    id              SERIAL PRIMARY KEY,
    project         TEXT,                  -- nullable = global
    key             TEXT NOT NULL,
    value           JSONB NOT NULL,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (project, key)
);

CREATE TABLE circuit_breaker_state (
    agent_id        TEXT PRIMARY KEY,
    open_until      TIMESTAMPTZ,
    consecutive_failures INTEGER NOT NULL DEFAULT 0,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Run migrations:

```bash
docker compose run --rm init-postgres
```

`init-postgres` is a small container that runs every `*.sql` in `infrastructure/postgres/migrations/` in order, idempotently (using a `schema_migrations` tracking table).

---

## How data lands here

The orchestrator subscribes to NATS subjects and writes to Postgres:

| NATS event | Postgres write |
|------------|----------------|
| Any event with `cost_metadata` | INSERT into `cost_events` |
| `task.completed` / `task.failed` / etc. | UPDATE counts in `audit_aggregates` |
| Circuit breaker trip | UPSERT `circuit_breaker_state` |

All inserts are idempotent (`UNIQUE (raw_event_id)`), so replaying NATS streams is safe.

---

## Useful queries

```sql
-- Daily spend by project, last 30 days
SELECT
  project,
  date_trunc('day', occurred_at) AS day,
  SUM(usd) AS spend_usd,
  COUNT(*) AS events
FROM cost_events
WHERE occurred_at > now() - interval '30 days'
GROUP BY 1, 2
ORDER BY 2 DESC, 1;

-- Top spending agents this month
SELECT agent_id, SUM(usd) AS total_usd, COUNT(*) AS tasks
FROM cost_events
WHERE occurred_at >= date_trunc('month', now())
GROUP BY agent_id
ORDER BY total_usd DESC
LIMIT 20;

-- Spend per task (for debugging runaway tasks)
SELECT task_id, project, SUM(usd) AS task_usd, COUNT(*) AS events
FROM cost_events
GROUP BY task_id, project
HAVING SUM(usd) > 1.00
ORDER BY task_usd DESC;
```

---

## Operator access

```bash
# Connect via psql
docker compose exec postgres psql -U ai_ao

# Or expose to host (already mapped to 5432)
psql -h localhost -U ai_ao -d ai_ao
```

---

## Backups

Standard Postgres backup. Daily via cron:

```bash
docker compose exec -T postgres pg_dump -U ai_ao ai_ao | gzip > /backup/pg-$(date +%Y%m%d).sql.gz
```

For PITR, configure WAL archiving — see [`runbooks/backup-restore.md`](runbooks/backup-restore.md).

---

## Production

For production, prefer:

- **Managed Postgres** (Supabase, Neon, AWS RDS, Cloud SQL) — eliminate operational burden
- Or self-hosted with replication (primary + read replica)

Either way, point `POSTGRES_*` env vars at the production instance and skip the Postgres container.

---

## Verification

```bash
# Up
docker compose exec postgres pg_isready -U ai_ao

# Schema migrated
docker compose exec postgres psql -U ai_ao -c "\dt"
# Should list: cost_events, audit_aggregates, policy_state, circuit_breaker_state, schema_migrations

# Insert test row (will be cleaned up by init in dev mode)
docker compose exec postgres psql -U ai_ao -c "
  INSERT INTO cost_events (occurred_at, task_id, project, agent_id, vendor, usd, raw_event_id)
  VALUES (now(), 'test-task', 'test-project', 'test-agent', 'test', 0.01, 'test-event');
  SELECT * FROM cost_events WHERE raw_event_id = 'test-event';
  DELETE FROM cost_events WHERE raw_event_id = 'test-event';
"
```

---

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `relation "cost_events" does not exist` | Migrations didn't run | `docker compose run --rm init-postgres` |
| Slow `cost_events` queries | Index missing | Re-run migrations; check `\d cost_events` |
| Unique constraint violation on inserts | Replay attempting to re-insert | This is expected; INSERT ... ON CONFLICT DO NOTHING in orchestrator |
