# Runbook — Reverse Proxy / Ingress

> Put a TLS-terminating reverse proxy in front of the stack for any internet-facing deployment. We recommend **Caddy** (auto-TLS) for single-VM deployments and **Traefik** for multi-host.

## Caddy (recommended for single VM)

`/etc/caddy/Caddyfile`:

```caddyfile
{
  email ops@example.com
}

aiao.example.com {
  encode gzip zstd

  # Orchestrator HTTP API
  handle /v1/* {
    reverse_proxy localhost:8080
  }

  # Health probes (keep open for monitoring)
  handle /healthz {
    reverse_proxy localhost:8080
  }

  # Grafana
  handle /grafana/* {
    reverse_proxy localhost:3000
  }

  # MinIO console (restrict by IP if exposed)
  handle /minio/* {
    @internal client_ip 10.0.0.0/8
    reverse_proxy @internal localhost:9001
    respond 403
  }

  # Default deny — anything else 404s
  handle { respond 404 }
}
```

Reload:
```bash
sudo caddy reload --config /etc/caddy/Caddyfile
```

## Traefik (multi-host or compose-native)

Add labels to each service in `docker-compose.yml`:

```yaml
orchestrator:
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.orch.rule=Host(`aiao.example.com`) && PathPrefix(`/v1`)"
    - "traefik.http.routers.orch.tls.certresolver=letsencrypt"
    - "traefik.http.services.orch.loadbalancer.server.port=8080"
```

## TLS for NATS (optional)

For external NATS clients (e.g., a remote Admin Portal), terminate TLS at NATS itself rather than the proxy — NATS protocol is not HTTP and most reverse proxies cannot speak it cleanly.

```conf
# nats-server.conf
tls {
  cert_file: /etc/nats/tls/cert.pem
  key_file:  /etc/nats/tls/key.pem
}
```

## Hardening checklist

- [ ] Only ports 443 (and 22 for SSH) open at the firewall
- [ ] HSTS enabled
- [ ] Rate limiting on `/v1/*` (Caddy: `rate_limit` directive)
- [ ] Basic-auth or mTLS on `/minio/*` and `/grafana/*` if not behind VPN
- [ ] Webhook endpoint `/webhook/*` must verify HMAC; never rely on IP allowlists alone
