# Runbook — Backup & Restore

> **Reminder:** Git is the system of record. Postgres + MinIO + NATS hold rebuildable state. **A full disaster recovery requires only the Git repo plus current `.env`.**

## What to back up

| Asset                                  | Frequency  | Method                                                |
| -------------------------------------- | ---------- | ----------------------------------------------------- |
| `infrastructure/.env`                  | On change  | Encrypted offline (1Password, age, etc.)              |
| `infrastructure/secrets/*`             | On change  | Encrypted offline                                     |
| Git repo (audit + state)               | Continuous | Already on GitHub; mirror to second remote optional   |
| Postgres                               | Daily      | `pg_dump` to MinIO (lifecycle keeps 30d)              |
| MinIO `aiao-artifacts`                 | Versioned  | Versioning enabled; replicate to second MinIO/S3      |
| NATS JetStream snapshots               | Hourly     | `nats stream backup` to MinIO                         |

## Daily Postgres backup (cron)

```bash
0 2 * * * docker exec aiao-postgres \
  pg_dump -U aiao -d aiao -Fc | \
  mc pipe local/aiao-artifacts/backups/postgres-$(date +%F).dump
```

## Restore procedure

### 1. Provision fresh VM, clone repo, restore .env

```bash
git clone https://github.com/<org>/gateforge-ai-ao
cd gateforge-ai-ao
# Restore .env and infrastructure/secrets/* from offline backup
```

### 2. Bring up storage substrates first

```bash
docker compose up -d nats minio postgres
```

### 3. Restore Postgres

```bash
mc cp local/aiao-artifacts/backups/postgres-YYYY-MM-DD.dump /tmp/
docker exec -i aiao-postgres pg_restore -U aiao -d aiao --clean --if-exists < /tmp/postgres-YYYY-MM-DD.dump
```

### 4. Restore MinIO buckets (if MinIO data lost)

```bash
mc mirror s3-replica/aiao-artifacts local/aiao-artifacts
```

### 5. Restore NATS JetStream

```bash
nats stream restore TASKS  /backup/tasks.snap
nats stream restore EVENTS /backup/events.snap
```

### 6. Bring up control plane + adapters

```bash
docker compose up -d
docker compose ps        # all healthy
./tools/smoke-test.sh    # confirm end-to-end
```

## Acceptable RTO / RPO

| Scenario                                | RTO       | RPO          |
| --------------------------------------- | --------- | ------------ |
| Single container failure                | < 1 min   | 0            |
| VM lost, restored from backups          | < 30 min  | < 1 day (PG) |
| Full data loss, rebuild from Git only   | < 1 hour  | 0 (audit)    |
