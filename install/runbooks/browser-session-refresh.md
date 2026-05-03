# Runbook — Browser Session Refresh (Manus & other browser-based adapters)

> **Trigger:** Manus adapter starts emitting `failed` with `error.code = AUTH_EXPIRED` or `SELECTOR_NOT_FOUND` on the login page.

## Why this is needed

Browser-based adapters reuse a Playwright `storageState` JSON to skip login. Sessions expire (~ weekly to monthly depending on vendor). When they do, every task fails fast.

## Refresh procedure (~5 min)

1. **Pause the adapter** (avoids storms of failed tasks during refresh):
   ```bash
   curl -X POST localhost:8080/v1/control/agent-pause -d '{"agent_id":"manus/v1"}'
   ```
2. **Refresh the session** on a workstation with a real browser:
   ```bash
   npx playwright codegen \
     --save-storage=infrastructure/secrets/manus-session.json \
     https://manus.im
   ```
   Log in, accept 2FA, close the window once you see your dashboard.
3. **Validate the file** is non-empty and contains cookies:
   ```bash
   jq '.cookies | length' infrastructure/secrets/manus-session.json
   ```
4. **Reload the adapter** to pick up the new file:
   ```bash
   docker compose restart adapter-manus
   ```
5. **Resume the agent**:
   ```bash
   curl -X POST localhost:8080/v1/control/agent-resume -d '{"agent_id":"manus/v1"}'
   ```
6. **Smoke test**:
   ```bash
   ./tools/smoke-test.sh   # with capability that routes to manus
   ```

## Automation (Phase 6+)

We plan to add a session-aging metric (`aiao_browser_session_age_hours`) and a Grafana alert at 5d. This runbook will then be triggered from PagerDuty rather than discovered by failed tasks.
