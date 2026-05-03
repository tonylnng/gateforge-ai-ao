#!/usr/bin/env bash
# =============================================================================
# chaos-test.sh — submit N long tasks, kill orchestrator mid-flight, assert
# all tasks reach a terminal state after recovery.
# =============================================================================
set -euo pipefail

ORCH_URL="${ORCH_URL:-http://localhost:8080}"
N="${N:-5}"
TASKS=()

echo ">> Submitting $N tasks..."
for i in $(seq 1 "$N"); do
  id="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
  TASKS+=("$id")
  curl -sS -X POST "$ORCH_URL/v1/tasks" -H "Content-Type: application/json" -d "{
    \"id\": \"$id\",
    \"capability\": \"echo\",
    \"input\": { \"sleep_ms\": 5000 },
    \"deadline_seconds\": 60
  }" >/dev/null
done

echo ">> Killing orchestrator..."
docker kill aiao-orchestrator >/dev/null
sleep 2
echo ">> Restarting orchestrator..."
docker start aiao-orchestrator >/dev/null

echo ">> Waiting for terminal states..."
deadline=$((SECONDS + 30))
done_count=0
while (( SECONDS < deadline )); do
  done_count=0
  for id in "${TASKS[@]}"; do
    state=$(curl -sS "$ORCH_URL/v1/tasks/$id" | jq -r .state 2>/dev/null || echo "unknown")
    [[ "$state" == "completed" || "$state" == "failed" ]] && done_count=$((done_count+1))
  done
  echo "   $done_count/$N terminal"
  (( done_count == N )) && break
  sleep 2
done

if (( done_count == N )); then
  echo "✓ chaos-test PASSED — no tasks lost"
  exit 0
fi
echo "✗ chaos-test FAILED — only $done_count/$N reached terminal" >&2
exit 1
