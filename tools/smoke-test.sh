#!/usr/bin/env bash
# =============================================================================
# smoke-test.sh — submit a single echo task and assert completion within 10s.
# =============================================================================
set -euo pipefail

ORCH_URL="${ORCH_URL:-http://localhost:8080}"
TASK_ID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"

echo ">> Submitting task $TASK_ID"
curl -sS -X POST "$ORCH_URL/v1/tasks" \
  -H "Content-Type: application/json" \
  -d "$(cat <<EOF
{
  "id": "$TASK_ID",
  "capability": "echo",
  "input": { "message": "hello aiao" },
  "deadline_seconds": 30
}
EOF
)" | tee /tmp/smoke-submit.json

echo
echo ">> Polling for terminal state (≤ 10s)..."
deadline=$((SECONDS + 10))
while (( SECONDS < deadline )); do
  state=$(curl -sS "$ORCH_URL/v1/tasks/$TASK_ID" | jq -r .state)
  echo "   state=$state"
  if [[ "$state" == "completed" || "$state" == "failed" ]]; then
    echo "✓ smoke-test reached terminal state: $state"
    exit 0
  fi
  sleep 1
done

echo "✗ smoke-test TIMED OUT" >&2
exit 1
