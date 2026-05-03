#!/usr/bin/env bash
# =============================================================================
# provision-jetstream.sh — apply infrastructure/nats/jetstream-streams.yaml
# Creates streams + durable consumers.  Idempotent.
# =============================================================================
set -euo pipefail

YAML="${1:-infrastructure/nats/jetstream-streams.yaml}"
NATS_URL="${NATS_URL:-nats://localhost:4222}"

if ! command -v nats >/dev/null; then
  echo "Install the NATS CLI:  https://github.com/nats-io/natscli/releases"
  exit 2
fi

# Streams ---------------------------------------------------------------------
yq '.streams[]' "$YAML" -o=json | while read -r s; do
  name=$(echo "$s" | jq -r .name)
  subjects=$(echo "$s" | jq -r '.subjects | join(",")')
  storage=$(echo "$s" | jq -r .storage)
  retention=$(echo "$s" | jq -r .retention)
  max_age=$(echo "$s" | jq -r .max_age)
  max_msgs=$(echo "$s" | jq -r .max_msgs)
  max_bytes=$(echo "$s" | jq -r .max_bytes)
  replicas=$(echo "$s" | jq -r .replicas)

  echo ">> stream: $name ($subjects)"
  nats stream add "$name" \
    --subjects="$subjects" \
    --storage="$storage" \
    --retention="$retention" \
    --max-age="$max_age" \
    --max-msgs="$max_msgs" \
    --max-bytes="$max_bytes" \
    --replicas="$replicas" \
    --discard=old --dupe-window=5m \
    --defaults --no-allow-rollup --no-deny-delete --no-deny-purge \
    --server="$NATS_URL" 2>/dev/null \
    || nats stream update "$name" --server="$NATS_URL"
done

# Consumers -------------------------------------------------------------------
yq '.consumers[]' "$YAML" -o=json | while read -r c; do
  stream=$(echo "$c" | jq -r .stream)
  name=$(echo "$c" | jq -r .name)
  ack=$(echo "$c" | jq -r .ack_policy)
  echo ">> consumer: $stream/$name (ack=$ack)"
  nats consumer add "$stream" "$name" --ack="$ack" --defaults \
    --server="$NATS_URL" 2>/dev/null \
    || echo "   (exists)"
done

echo "✓ JetStream provisioned."
