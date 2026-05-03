#!/bin/bash
# =============================================================================
# Postgres init hook — runs ONCE on fresh data directory.
# Applies migrations from /docker-entrypoint-initdb.d/migrations/.
# =============================================================================
set -e

MIGRATIONS_DIR=/docker-entrypoint-initdb.d/migrations
if [ -d "$MIGRATIONS_DIR" ]; then
  for f in "$MIGRATIONS_DIR"/*.sql; do
    [ -e "$f" ] || continue
    echo ">> Applying migration: $f"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$f"
  done
fi

echo "✓ Postgres init hooks complete."
