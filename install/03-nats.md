# 03 — NATS JetStream

This guide explains the NATS configuration, stream definitions, KV buckets, authentication, and how to operate the broker.

---

## What's deployed

A single `nats:2.10.20-alpine` container with JetStream enabled, persistent storage, and HTTP monitoring on port 8222.

For production, switch to a 3-node cluster — see [Production clustering](#production-clustering).

---

## Container

Defined in `infrastructure/docker-compose.yml`:

```yaml
nats:
  image: nats:2.10.20-alpine
  container_name: ai-ao-nats
  restart: unless-stopped
  command: ["-c", "/etc/nats/nats-server.conf"]
  ports:
    - "4222:4222"   # client connections
    - "8222:8222"   # HTTP monitoring
  volumes:
    - ./nats/nats-server.conf:/etc/nats/nats-server.conf:ro
    - nats-data:/var/lib/nats
  healthcheck:
    test: ["CMD-SHELL", "wget -q -O- http://localhost:8222/healthz | grep -q ok"]
    interval: 10s
    timeout: 3s
    retries: 5
```

---

## Server configuration

`infrastructure/nats/nats-server.conf`:

```
server_name: ai-ao-nats-1
listen: 0.0.0.0:4222
http: 0.0.0.0:8222

jetstream {
  store_dir: /var/lib/nats/jetstream
  max_memory_store: 1GB
  max_file_store: 50GB
  domain: ai-ao
}

# Authentication
authorization {
  users: [
    # Bootstrap token; replace with operator/JWT in production
    { user: "ai-ao", password: "$2a$11$..." }
  ]
}

# Limits
max_payload: 8MB
max_pending: 256MB
ping_interval: "20s"
max_outstanding_pings: 3

# Logging
logtime: true
debug: false
trace: false

# Monitoring
http_port: 8222
```

For production with JWT-based auth, see [`10-security.md`](10-security.md).

---

## Streams

Streams are pre-created by the `init-nats` container, which reads `infrastructure/nats/jetstream-streams.yaml`.

| Stream | Subjects | Retention | Storage | Max age | Max size | Replicas |
|--------|----------|-----------|---------|---------|----------|---------:|
| `TASKS` | `project.*.task.>` | limits | file | 30d | 10 GB | 1 (3 in prod) |
| `AGENTS` | `agent.>` | limits | file | 7d | 1 GB | 1 |
| `REGISTRY` | `registry.>` | limits | file | 7d | 500 MB | 1 |
| `AUDIT` | `audit.>` | limits | file | 365d | 50 GB | 1 |
| `DLQ` | `*.dlq` | limits | file | 30d | 5 GB | 1 |

Stream definition file format (excerpt):

```yaml
# infrastructure/nats/jetstream-streams.yaml
streams:
  - name: TASKS
    subjects: ["project.*.task.>"]
    retention: limits
    storage: file
    max_age: 720h        # 30 days
    max_bytes: 10737418240
    max_msg_size: 8388608
    discard: old
    duplicate_window: 24h    # idempotency window
    num_replicas: 1
```

### Re-create or update streams

```bash
# Add or modify a stream definition in the YAML, then:
docker compose run --rm init-nats

# Or manually:
docker compose exec nats nats stream add --config /streams/tasks.yaml
docker compose exec nats nats stream update TASKS --config /streams/tasks.yaml
```

---

## KV buckets

| Bucket | Purpose | TTL | Max value size |
|--------|---------|-----|---------------:|
| `agents` | Live agent registry (current cards) | none | 32 KB |
| `seen` | Idempotency seen-set | 24h | 256 B |
| `task_state` | Latest known task state per task_id | 30d | 4 KB |
| `policy` | Live policy snapshot | none | 16 KB |

Pre-created by `init-nats`:

```yaml
# infrastructure/nats/jetstream-streams.yaml (continued)
kv_buckets:
  - name: agents
    history: 5
    storage: file
  - name: seen
    ttl: 24h
    storage: file
  - name: task_state
    history: 10
    ttl: 720h
    storage: file
  - name: policy
    history: 20
    storage: file
```

---

## Authentication

Two modes supported:

### Mode A: shared secret (dev only)

`.env` sets `NATS_BOOTSTRAP_USER` and `NATS_BOOTSTRAP_PASSWORD`. All services use this. Sufficient for single-VM dev.

### Mode B: NKEY/JWT (production)

Each agent gets a per-agent JWT signed by an operator key. JWT scopes restrict subjects each agent can publish/subscribe.

Setup walkthrough in [`10-security.md`](10-security.md).

---

## Operator commands

Install the `nats` CLI on the host:

```bash
curl -sf https://binaries.nats.dev/nats-io/natscli/nats@v0.1.6 | sh
sudo mv nats /usr/local/bin/
nats context add ai-ao --server nats://localhost:4222 --user ai-ao --password $NATS_BOOTSTRAP_PASSWORD
nats context select ai-ao
```

Common operations:

```bash
# List streams
nats stream ls

# Describe a stream
nats stream info TASKS

# Tail messages on a subject (live)
nats sub "project.>"

# Replay a stream from beginning to a specific subject
nats stream view TASKS

# Inspect KV bucket
nats kv ls
nats kv watch agents

# Purge a stream (DESTRUCTIVE — dev only)
nats stream purge TASKS --force
```

---

## Production clustering

For HA, run a 3-node JetStream cluster. Override file:

```yaml
# infrastructure/docker-compose.prod.yml
services:
  nats:
    deploy:
      replicas: 3
    command: ["-c", "/etc/nats/nats-cluster.conf"]
    volumes:
      - ./nats/nats-cluster.conf:/etc/nats/nats-cluster.conf:ro
```

Cluster config is in `infrastructure/nats/nats-cluster.conf` and adds:

```
cluster {
  name: ai-ao
  listen: 0.0.0.0:6222
  routes: [
    nats-route://nats-1:6222
    nats-route://nats-2:6222
    nats-route://nats-3:6222
  ]
}
```

All streams must have `num_replicas: 3` in production.

---

## Disk and resource sizing

| Workload | Disk | RAM | CPU |
|----------|------|----:|----:|
| Dev / personal | 50 GB | 1 GB | 0.5 |
| Small team (10k tasks/day) | 200 GB | 2 GB | 1 |
| Production (1M tasks/day, 3 nodes) | 500 GB SSD/node | 4 GB/node | 2/node |

Stream `max_bytes` should be ~70% of dedicated disk to leave headroom.

---

## Backups

JetStream data lives in `/var/lib/nats/jetstream` (the Docker volume `nats-data`).

```bash
# Snapshot stream (no downtime)
nats stream backup TASKS /backup/tasks-$(date +%Y%m%d).tgz

# Restore
nats stream restore /backup/tasks-20260503.tgz
```

Schedule via cron, ship to off-VM storage. See [`runbooks/backup-restore.md`](runbooks/backup-restore.md).

---

## Verification

After bringing NATS up:

```bash
# Healthy
curl -s http://localhost:8222/healthz | jq
# {"status":"ok"}

# JetStream initialized
curl -s http://localhost:8222/jsz?streams=true | jq '.streams | map(.name)'
# ["TASKS","AGENTS","REGISTRY","AUDIT","DLQ"]

# KV buckets created
nats kv ls
# agents, seen, task_state, policy

# Round-trip publish/subscribe
nats pub test.hello "world"
# Published

nats sub test.hello --count=1
# [#1] Received on "test.hello"
# world
```

If all four checks pass, NATS is ready.

---

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `connection refused` on 4222 | Container not up | `docker compose ps`; check logs |
| Streams missing | `init-nats` not run | `docker compose run --rm init-nats` |
| `slow consumer detected` warnings | Subscriber falling behind | Increase consumer ack pending, scale consumers |
| Disk fills up | Stream retention too generous | Lower `max_bytes` or `max_age` per stream |
| `auth violation` errors | Wrong credentials | Check `.env` matches `nats-server.conf` |
