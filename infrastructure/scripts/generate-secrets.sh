#!/usr/bin/env bash
# =============================================================================
# generate-secrets.sh — fills empty secret values in .env with random strings
# =============================================================================
# Idempotent: only fills keys whose value is empty in .env.
# Re-run safely; existing values are preserved.
#
# Usage:
#   ./scripts/generate-secrets.sh           # operates on ./.env
#   ./scripts/generate-secrets.sh path/.env
# =============================================================================
set -euo pipefail

ENV_FILE="${1:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Run: cp .env.example .env" >&2
  exit 1
fi

# Cross-platform random hex (32 bytes -> 64 char)
rand_hex() { openssl rand -hex 32; }
rand_b64() { openssl rand -base64 36 | tr -d '=+/' | cut -c1-40; }
rand_pw()  { openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-32; }

declare -A FILLERS=(
  [MINIO_ROOT_PASSWORD]="$(rand_pw)"
  [MINIO_ACCESS_KEY]="$(rand_b64)"
  [MINIO_SECRET_KEY]="$(rand_b64)"
  [POSTGRES_PASSWORD]="$(rand_pw)"
  [GRAFANA_ADMIN_PASSWORD]="$(rand_pw)"
  [ORCH_HMAC_SECRET]="$(rand_hex)"
  [GITHUB_WEBHOOK_SECRET]="$(rand_hex)"
)

backup="${ENV_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
cp "$ENV_FILE" "$backup"
echo "Backup written to $backup"

for key in "${!FILLERS[@]}"; do
  # Match KEY= (empty value), not KEY=something
  if grep -qE "^${key}=$" "$ENV_FILE"; then
    val="${FILLERS[$key]}"
    # macOS/BSD sed compatibility
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|^${key}=$|${key}=${val}|" "$ENV_FILE"
    else
      sed -i "s|^${key}=$|${key}=${val}|" "$ENV_FILE"
    fi
    echo "  filled: $key"
  else
    echo "  skipped: $key (already set or missing)"
  fi
done

echo
echo "Done. Review with:  diff $backup $ENV_FILE"
echo "Secrets stored only in $ENV_FILE — keep that file out of Git."
