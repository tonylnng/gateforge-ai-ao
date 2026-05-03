-- =============================================================================
-- GateForge AI-AO — Postgres schema (initial)
-- =============================================================================
-- IMPORTANT: Postgres is NOT the system of record.  Git is.
-- This database holds:
--   * cost aggregates (per task, per agent, per day)
--   * audit aggregates (decision counts, breaker state)
--   * routing-policy materialized state (current breaker open/closed)
--
-- All rows here can be REBUILT by replaying NATS AUDIT + EVENTS streams.
-- Do not place anything irreplaceable here.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- -----------------------------------------------------------------------------
-- agents — one row per registered adapter/agent (mirror of Git agent-card.yaml)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agents (
  id                TEXT PRIMARY KEY,                  -- e.g. "perplexity-computer/v1"
  display_name      TEXT NOT NULL,
  vendor            TEXT NOT NULL,
  capabilities      TEXT[] NOT NULL DEFAULT '{}',
  protocol_version  TEXT NOT NULL,
  enabled           BOOLEAN NOT NULL DEFAULT true,
  registered_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_agents_caps ON agents USING gin (capabilities);

-- -----------------------------------------------------------------------------
-- task_costs — per-task rollup, written when EVENTS.completed arrives
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS task_costs (
  task_id            UUID PRIMARY KEY,
  agent_id           TEXT NOT NULL REFERENCES agents(id),
  capability         TEXT NOT NULL,
  started_at         TIMESTAMPTZ NOT NULL,
  completed_at       TIMESTAMPTZ NOT NULL,
  duration_ms        BIGINT NOT NULL,
  tokens_input       BIGINT NOT NULL DEFAULT 0,
  tokens_output      BIGINT NOT NULL DEFAULT 0,
  cost_usd           NUMERIC(12,6) NOT NULL DEFAULT 0,
  outcome            TEXT NOT NULL,                    -- ok|fail|cancel|timeout
  retry_count        INT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_task_costs_agent_day
  ON task_costs (agent_id, date_trunc('day', started_at));
CREATE INDEX IF NOT EXISTS idx_task_costs_capability
  ON task_costs (capability);

-- -----------------------------------------------------------------------------
-- breaker_state — circuit breaker per (agent, capability) pair
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS breaker_state (
  agent_id           TEXT NOT NULL,
  capability         TEXT NOT NULL,
  state              TEXT NOT NULL DEFAULT 'closed',   -- closed|open|half_open
  failure_count      INT NOT NULL DEFAULT 0,
  last_failure_at    TIMESTAMPTZ,
  opened_at          TIMESTAMPTZ,
  next_probe_at      TIMESTAMPTZ,
  PRIMARY KEY (agent_id, capability)
);

-- -----------------------------------------------------------------------------
-- audit_log — flat, append-only mirror of NATS aiao.audit.* (rebuildable)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id                 BIGSERIAL PRIMARY KEY,
  event_id           UUID UNIQUE NOT NULL,
  event_type         TEXT NOT NULL,                    -- e.g. routing.decided
  task_id            UUID,
  actor              TEXT NOT NULL,
  occurred_at        TIMESTAMPTZ NOT NULL,
  payload            JSONB NOT NULL,
  signature          TEXT                              -- HMAC of payload
);
CREATE INDEX IF NOT EXISTS idx_audit_task    ON audit_log (task_id);
CREATE INDEX IF NOT EXISTS idx_audit_type    ON audit_log (event_type);
CREATE INDEX IF NOT EXISTS idx_audit_time    ON audit_log (occurred_at DESC);

-- -----------------------------------------------------------------------------
-- budget_state — daily/monthly spend rollups for the policy budget guard
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS budget_state (
  scope              TEXT NOT NULL,                    -- 'global' or agent_id
  period             DATE NOT NULL,                    -- start of day or month
  granularity        TEXT NOT NULL,                    -- 'day' or 'month'
  spent_usd          NUMERIC(14,6) NOT NULL DEFAULT 0,
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (scope, period, granularity)
);

-- -----------------------------------------------------------------------------
-- schema_version — tracked by orchestrator's migrator
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_version (
  version            INT PRIMARY KEY,
  applied_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  description        TEXT
);
INSERT INTO schema_version (version, description)
VALUES (1, 'initial schema — agents, task_costs, breaker_state, audit_log, budget_state')
ON CONFLICT DO NOTHING;
