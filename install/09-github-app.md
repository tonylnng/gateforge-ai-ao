# 09 — GitHub App

AI-AO uses a GitHub App as its identity for reading/writing project repos and receiving webhooks.

---

## Why a GitHub App (not a PAT)

- Fine-grained per-repo permissions
- Higher rate limits (~5000–15000 req/hour per installation)
- App-level webhook delivery
- Auditable identity (commits show as the App)
- Per-installation tokens, rotatable, scoped

---

## Step-by-step setup

### 1. Create the App

Go to GitHub → Settings → Developer settings → GitHub Apps → New GitHub App.

Fill in:

| Field | Value |
|-------|-------|
| GitHub App name | `gateforge-ai-ao-<your-name>` (must be globally unique) |
| Homepage URL | `https://gateforge.toniclab.ai` (or your URL) |
| Webhook URL | `https://<PUBLIC_HOST>/v1/webhooks/github` |
| Webhook secret | a random 64-char string — save this |

### 2. Permissions

Repository permissions:

| Permission | Access |
|------------|--------|
| Actions | Read |
| Checks | Read & write |
| Commit statuses | Read & write |
| Contents | Read & write |
| Deployments | Read & write |
| Issues | Read & write |
| Metadata | Read |
| Pages | Read |
| Pull requests | Read & write |
| Webhooks | Read & write |
| Workflows | Read & write |

Organization permissions: none required for personal use; add `Members: read` if you want team-aware routing.

### 3. Subscribe to events

Subscribe to:

- Issues
- Issue comments
- Push
- Pull request
- Pull request review
- Pull request review comment
- Workflow run (optional)

### 4. Where can this GitHub App be installed?

Choose:

- "Only on this account" for personal use
- "Any account" for productized use (when you go multi-tenant)

### 5. Create

Click **Create GitHub App**. You're now on the App's settings page.

### 6. Generate a private key

Scroll to **Private keys** → **Generate a private key**. Download the `.pem` file.

```bash
sudo mkdir -p /opt/secrets
sudo mv ~/Downloads/<your-app>.<date>.private-key.pem /opt/secrets/ai-ao-gh-app.pem
sudo chmod 600 /opt/secrets/ai-ao-gh-app.pem
sudo chown root:root /opt/secrets/ai-ao-gh-app.pem
```

### 7. Note the App ID

At the top of the App settings page. It's a number like `123456`.

### 8. Update `.env`

```bash
cd /opt/gateforge-ai-ao/infrastructure
${EDITOR:-vi} .env

# Set:
GH_APP_ID=123456
GH_APP_PRIVATE_KEY_PATH=/opt/secrets/ai-ao-gh-app.pem
GITHUB_WEBHOOK_SECRET=<the random secret you set>
```

### 9. Install the App on your project repos

GitHub → Settings → Developer settings → GitHub Apps → your App → Install App.

Choose the account/org, then choose **Only select repositories** and pick the repos AI-AO will manage.

### 10. Restart the orchestrator

```bash
docker compose restart orchestrator
docker compose logs -f orchestrator | head -50
```

Expected log lines:

```
INFO  github.app.authenticated    app_id=123456
INFO  github.installations.found  count=1
INFO  webhook.listener.ready      path=/v1/webhooks/github
```

---

## Webhook delivery

GitHub will start delivering webhook events. To verify:

```bash
# In GitHub: App settings → Advanced → Recent Deliveries
# Look for green checkmarks (200 OK responses)
```

If deliveries fail:

- Confirm `https://<PUBLIC_HOST>` is reachable from GitHub (use `smee.io` for local dev tunneling)
- Confirm `GITHUB_WEBHOOK_SECRET` matches both the App config and the orchestrator env
- Check orchestrator logs for HMAC verification errors

---

## Local development with smee.io

For local dev without a public DNS:

```bash
# Install
npm install -g smee-client

# Start tunnel
smee --url https://smee.io/<random-token> --target http://localhost:8080/v1/webhooks/github

# Set the App's webhook URL to https://smee.io/<random-token>
```

---

## Per-project installation

Each project repo where you want AI-AO to operate must have the App installed. The orchestrator uses the App's installation token (auto-rotated every hour) to read and write the repo.

If you add a new project later, install the App on the new repo. The orchestrator picks up the new installation on its next poll (or you can hit `POST /v1/admin/refresh-installations` to force).

---

## Verification

```bash
# Orchestrator authenticated
curl -s http://localhost:8080/v1/health | jq .github
# {"app_authenticated": true, "installations": 1}

# Test webhook delivery (in GitHub: App settings → Advanced → "Redeliver" the most recent ping)
docker compose logs orchestrator | grep webhook.received
# INFO  webhook.received  event=ping installation_id=...
```

---

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `unauthorized` from GitHub API | Wrong App ID or private key | Re-download .pem; verify `GH_APP_ID` |
| `webhook signature mismatch` | Secret mismatch | Check both ends |
| `No installations found` | App not installed on any repo | Install via GitHub UI |
| `404 Not Found` reading a repo | App not installed on that specific repo | Install on that repo |
| Rate limited | Too many concurrent operations | Increase per-installation rate via App tier, or add caching |
