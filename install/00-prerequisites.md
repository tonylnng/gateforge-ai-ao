# 00 — Prerequisites

Before installing AI-AO, ensure your environment meets these requirements.

---

## VM sizing

| Use case | vCPU | RAM | Disk | Notes |
|----------|-----:|----:|-----:|-------|
| Personal dev / single user | 4 | 8 GB | 100 GB | All components co-located |
| Small team trial | 8 | 16 GB | 200 GB | Same layout, more headroom |
| Production | 3+ VMs (split) | varies | varies | See production layout in `01-components.md` |

The single-VM stack runs comfortably on common cloud sizes:
- AWS: `t3.large` (dev), `m6i.xlarge` (small team)
- GCP: `e2-standard-4` (dev), `n2-standard-8` (small team)
- Azure: `Standard_D4s_v5` (dev), `Standard_D8s_v5` (small team)
- Hetzner / OVH / self-hosted: equivalent specs

---

## Operating system

**Recommended:** Ubuntu 22.04 LTS or 24.04 LTS.

Other supported distros: Debian 12+, Rocky Linux 9+, AlmaLinux 9+. Any modern Linux with Docker support works.

macOS is supported for development only via Docker Desktop. Production deployments must be Linux.

---

## Software dependencies

### Required

| Dependency | Min version | Install command (Ubuntu) |
|------------|-------------|-----------------------|
| Docker Engine | 24.0 | `curl -fsSL https://get.docker.com | sh` |
| Docker Compose | v2.20 | included with Docker Engine 24+ |
| Git | 2.34 | `sudo apt install -y git` |
| OpenSSL | 3.0 | `sudo apt install -y openssl` |
| jq | 1.6 | `sudo apt install -y jq` |
| curl | 7.80 | `sudo apt install -y curl` |

### Optional (for development / debugging)

| Dependency | Purpose |
|------------|---------|
| `nats` CLI | Inspect NATS streams and messages |
| `mc` (MinIO client) | Inspect MinIO buckets |
| `psql` | Query Postgres directly |
| Go 1.22+ | Build orchestrator and adapters from source |
| Node 20+ | Build TypeScript SDK |

---

## Network requirements

### Inbound (from the internet, if exposed)

| Port | Service | Notes |
|------|---------|-------|
| 443 | Caddy / nginx (TLS termination) | Public HTTPS for orchestrator API + Admin Portal |
| 22 | SSH | Operator access only |

### Internal (between containers, never exposed)

| Port | Service |
|------|---------|
| 4222 | NATS client |
| 8222 | NATS monitoring |
| 9000 | MinIO S3 |
| 9001 | MinIO console |
| 5432 | Postgres |
| 3000 | Grafana |
| 3100 | Loki |
| 3200 | Tempo |
| 4317, 4318 | OTel Collector |
| 8080 | Orchestrator |

### Outbound

The stack must reach:

- `api.github.com` and `*.github.com` (GitHub App, repo I/O)
- Vendor APIs of agent platforms you use (e.g. `api.perplexity.ai`)
- Image registries on first pull (`docker.io`, `ghcr.io`)

---

## DNS and TLS

For local dev, no DNS or TLS is needed; everything binds to `127.0.0.1`.

For production:

- Reserve a domain or subdomain (e.g. `ai-ao.example.com`)
- Issue a TLS certificate (Caddy auto-issues via Let's Encrypt is the easiest path)
- Configure DNS A/AAAA record to point to the VM

---

## GitHub access

You need:

1. A GitHub account that owns the project repos AI-AO will manage
2. Permission to install GitHub Apps on those repos (account owner or org admin)
3. The repo `tonylnng/gateforge-ai-ao` cloned locally for configs

GitHub App setup is in [`09-github-app.md`](09-github-app.md).

---

## Pre-flight verification

Run this on your fresh VM. All commands should succeed.

```bash
# Docker
docker --version          # Docker version 24.0+
docker compose version    # Docker Compose version v2.20+

# Permissions (your user can run docker without sudo)
docker run --rm hello-world

# Git
git --version

# Tools
jq --version
openssl version
curl --version

# Disk space
df -h /  # at least 50 GB free

# RAM
free -h  # at least 8 GB total

# Network reachability
curl -sS -o /dev/null -w "%{http_code}\n" https://api.github.com    # expect 200
curl -sS -o /dev/null -w "%{http_code}\n" https://docker.io          # expect 200 or 301
```

If all checks pass, proceed to [`01-components.md`](01-components.md).

---

## Common pre-install issues

| Symptom | Fix |
|---------|-----|
| `docker: permission denied` | `sudo usermod -aG docker $USER && newgrp docker` |
| `docker compose: command not found` | Update Docker Engine to 24+ or install Compose v2 plugin |
| Disk space tight | Move Docker storage: edit `/etc/docker/daemon.json` and set `data-root` to a larger volume |
| `apt` cannot find packages | `sudo apt update && sudo apt upgrade -y` |
| Behind a corporate proxy | Configure `~/.docker/config.json` and `systemd` proxy; see `runbooks/proxy.md` |
