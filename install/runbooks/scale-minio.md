# Runbook — Scale MinIO

> When `aiao-artifacts` exceeds 80% of its quota or single-disk performance is the bottleneck.

## Vertical scale (single-VM)

1. Stop MinIO container:
   ```bash
   docker compose stop minio
   ```
2. Attach a larger volume to the host, mount it at the same path used by the `minio_data` named volume.
3. Rsync existing data:
   ```bash
   rsync -aHAX /old/path/ /new/path/
   ```
4. Update the volume binding in `docker-compose.yml` (or grow the named volume's underlying disk).
5. Start MinIO:
   ```bash
   docker compose up -d minio
   ```

## Horizontal scale (distributed mode)

Distributed MinIO requires a fresh deployment — you cannot convert single-node to distributed in place. Path:

1. Stand up a new 4-node MinIO cluster (separate VMs or pods):
   ```bash
   docker compose -f docker-compose.minio-distributed.yml up -d
   ```
2. Mirror data from the old node:
   ```bash
   mc mirror old/aiao-artifacts new-cluster/aiao-artifacts
   mc mirror old/aiao-logs      new-cluster/aiao-logs
   mc mirror old/aiao-traces    new-cluster/aiao-traces
   ```
3. Update `.env` `MINIO_HOST` to point at the new cluster ingress.
4. Restart orchestrator + adapters; verify with smoke-test.

## Quota & lifecycle adjustments

```bash
# Bump quota
mc admin bucket quota local/aiao-artifacts --size 200GB

# Tighten lifecycle (e.g. expire in 180d instead of 365)
mc ilm import local/aiao-artifacts < infrastructure/minio/lifecycle.json
```

## Validation

```bash
mc admin info local
mc admin heal -r local
./tools/smoke-test.sh
```
