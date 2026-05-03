# Runbook — Secret Rotation

> Rotate quarterly OR immediately on suspected leak.

## Inventory

| Secret                       | Where it lives                              | Rotate by                            |
| ---------------------------- | ------------------------------------------- | ------------------------------------ |
| `MINIO_ROOT_PASSWORD`        | `.env`                                      | `mc admin user password local`       |
| `MINIO_ACCESS_KEY/SECRET`    | `.env`                                      | `mc admin user svcacct rm` + recreate |
| `POSTGRES_PASSWORD`          | `.env`                                      | `ALTER USER aiao WITH PASSWORD '…';` |
| `GRAFANA_ADMIN_PASSWORD`     | `.env`                                      | Reset via Grafana CLI                |
| `ORCH_HMAC_SECRET`           | `.env`                                      | Roll with grace window (see below)   |
| `GITHUB_WEBHOOK_SECRET`      | `.env` + GitHub App settings                | Update both, then restart            |
| `ADAPTER_PPLX_API_KEY`       | `.env`                                      | Re-issue in Perplexity dashboard     |
| Manus session                | `infrastructure/secrets/manus-session.json` | See [browser-session-refresh.md](browser-session-refresh.md) |

## HMAC rotation with zero downtime

The orchestrator supports **two active HMAC keys** during rotation:

```bash
# 1. Add the new secret as the secondary key.
echo "ORCH_HMAC_SECRET_NEXT=$(openssl rand -hex 32)" >> .env

# 2. Reload orchestrator (SIGHUP).
docker compose kill -s HUP orchestrator

# 3. Update GitHub App webhook secret to the new value.
#    GitHub may send events signed with old or new for ~1h.

# 4. After 1 hour, swap.
sed -i 's/^ORCH_HMAC_SECRET=.*/ORCH_HMAC_SECRET='"$NEW"'/' .env
sed -i '/^ORCH_HMAC_SECRET_NEXT=/d' .env
docker compose kill -s HUP orchestrator
```

## Verify after rotation

```bash
./tools/smoke-test.sh        # end-to-end still works
curl -sS localhost:8080/healthz
docker compose logs --tail=20 orchestrator | grep -i secret
```
