# 04 — MinIO

S3-compatible object store for AI-AO artifacts.

---

## What's deployed

A single `minio/minio` container with persistent storage, S3 API on 9000, web console on 9001.

For production, switch to a distributed MinIO deployment — see [Production scaling](#production-scaling).

---

## Container

```yaml
# infrastructure/docker-compose.yml (excerpt)
minio:
  image: minio/minio:RELEASE.2025-01-20T14-49-07Z
  container_name: ai-ao-minio
  restart: unless-stopped
  command: server /data --console-address ":9001"
  ports:
    - "9000:9000"
    - "9001:9001"
  environment:
    MINIO_ROOT_USER: ${MINIO_ROOT_USER}
    MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    MINIO_BROWSER_REDIRECT_URL: http://${PUBLIC_HOST}:9001
  volumes:
    - minio-data:/data
  healthcheck:
    test: ["CMD-SHELL", "curl -sf http://localhost:9000/minio/health/live"]
    interval: 10s
    timeout: 3s
    retries: 5
```

---

## Buckets

Buckets are created by `init-minio` reading `infrastructure/minio/buckets.yaml`:

| Bucket | Purpose | Versioning | Lifecycle |
|--------|---------|:-:|-----------|
| `gateforge-artifacts` | All task artifacts | yes | move to cold tier after 90d, delete after 365d |
| `gateforge-audit-blobs` | Large audit payloads (rare) | yes | delete after 730d |
| `gateforge-tmp` | Adapter scratch space | no | delete after 7d |

Bucket file:

```yaml
# infrastructure/minio/buckets.yaml
buckets:
  - name: gateforge-artifacts
    versioning: enabled
    lifecycle:
      - id: cold-after-90d
        status: enabled
        transition:
          days: 90
          storage_class: STANDARD_IA
      - id: delete-after-365d
        status: enabled
        expiration:
          days: 365

  - name: gateforge-audit-blobs
    versioning: enabled
    lifecycle:
      - id: delete-after-730d
        status: enabled
        expiration:
          days: 730

  - name: gateforge-tmp
    versioning: disabled
    lifecycle:
      - id: delete-after-7d
        status: enabled
        expiration:
          days: 7
```

---

## Object key conventions

```
gateforge-artifacts/<project>/<task_id>/<artifact_name>
gateforge-tmp/<adapter_id>/<task_id>/<filename>
```

Examples:

```
gateforge-artifacts/gateforge-travel/01HXYZAB.../research-report.pdf
gateforge-artifacts/gateforge-travel/01HXYZAB.../sources.json
gateforge-tmp/perplexity-computer-prod/01HXYZAB.../partial-output.txt
```

Adapters compute SHA256 of every artifact and include it in the `task.completed` event.

---

## Access policies

Adapters get scoped credentials. The orchestrator generates per-adapter access keys via the MinIO admin API. Each adapter can only read and write under its own task's prefix.

For dev, all containers share the root credentials via `.env`. See [`10-security.md`](10-security.md) for production credential issuance.

---

## Operator access

```bash
# Install mc (MinIO client) on host
curl -O https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc && sudo mv mc /usr/local/bin/

# Configure
mc alias set ai-ao http://localhost:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

# List buckets and contents
mc ls ai-ao
mc ls --recursive ai-ao/gateforge-artifacts

# Inspect lifecycle
mc ilm rule list ai-ao/gateforge-artifacts

# Download an artifact
mc cp ai-ao/gateforge-artifacts/proj/task-id/file.pdf ./

# Disk usage
mc du ai-ao
```

---

## Production scaling

Single-node is fine until you outgrow ~10 TB or need HA. Then switch to distributed mode (4+ nodes, EC: 4+2 default).

```yaml
# infrastructure/docker-compose.prod.yml (sketch)
services:
  minio-1: { ... }
  minio-2: { ... }
  minio-3: { ... }
  minio-4: { ... }
  # all four in a Compose deploy with shared command:
  # server http://minio-{1...4}/data
```

For multi-VM production, run MinIO on its own VM(s). See [`runbooks/scale-minio.md`](runbooks/scale-minio.md).

---

## Backups

```bash
# Mirror to external S3 (e.g. Backblaze, Wasabi, Cloudflare R2)
mc mirror --watch ai-ao/gateforge-artifacts external/backup-bucket

# Or one-shot snapshot
mc cp --recursive ai-ao/gateforge-artifacts/ /mnt/backup/$(date +%Y%m%d)/
```

Backup runbook: [`runbooks/backup-restore.md`](runbooks/backup-restore.md).

---

## Verification

```bash
# Live
curl -sf http://localhost:9000/minio/health/live
# 200 OK

# Buckets exist
mc ls ai-ao | grep -E 'gateforge-(artifacts|audit-blobs|tmp)'
# All three should appear

# Lifecycle rules applied
mc ilm rule list ai-ao/gateforge-artifacts
# Should show cold-after-90d and delete-after-365d

# Round-trip
echo "test" | mc pipe ai-ao/gateforge-tmp/test.txt
mc cat ai-ao/gateforge-tmp/test.txt
mc rm ai-ao/gateforge-tmp/test.txt
```

---

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Console returns 502 | Wrong `MINIO_BROWSER_REDIRECT_URL` | Set to a URL the browser can reach |
| `Access Denied` from adapter | Per-adapter creds not issued | Run policy issuance script in `tools/` |
| Disk fills up | Lifecycle policies missing | Re-run `init-minio` |
| Slow uploads from adapter | Single-node EC=0 (no parity); at scale switch to distributed | See production scaling |
