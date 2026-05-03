#!/usr/bin/env bash
# =============================================================================
# load-test.sh — sustained RPS probe.  Uses `vegeta` if available, else curl.
# =============================================================================
set -euo pipefail

RPS="${RPS:-10}"
DURATION="${DURATION:-30s}"
ORCH_URL="${ORCH_URL:-http://localhost:8080}"

if ! command -v vegeta >/dev/null; then
  echo "Install vegeta:  brew install vegeta   OR   go install github.com/tsenart/vegeta@latest"
  exit 2
fi

echo ">> Targeting $ORCH_URL @ ${RPS} rps for $DURATION"

cat > /tmp/aiao-target.json <<'EOF'
POST http://localhost:8080/v1/tasks
Content-Type: application/json
@/tmp/aiao-payload.json
EOF

cat > /tmp/aiao-payload.json <<'EOF'
{ "capability": "echo", "input": { "message": "loadtest" }, "deadline_seconds": 30 }
EOF

vegeta attack -rate="$RPS" -duration="$DURATION" -targets=/tmp/aiao-target.json \
  | tee /tmp/results.bin \
  | vegeta report
