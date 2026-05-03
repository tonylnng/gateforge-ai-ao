#!/bin/sh
# =============================================================================
# MinIO bootstrap — runs once via the minio-bootstrap docker-compose service.
# Creates buckets, applies lifecycle, and provisions a service account.
# Idempotent: safe to re-run; existing resources are skipped.
# =============================================================================
set -e

ALIAS=local
ENDPOINT=http://minio:9000

echo ">> Configuring mc alias..."
mc alias set "$ALIAS" "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

create_bucket() {
  local b="$1"
  if mc ls "$ALIAS/$b" >/dev/null 2>&1; then
    echo "   bucket exists: $b"
  else
    mc mb "$ALIAS/$b"
    echo "   bucket created: $b"
  fi
}

echo ">> Creating buckets..."
create_bucket "$MINIO_BUCKET_ARTIFACTS"
create_bucket "$MINIO_BUCKET_LOGS"
create_bucket "$MINIO_BUCKET_TRACES"

echo ">> Enabling versioning on artifacts..."
mc version enable "$ALIAS/$MINIO_BUCKET_ARTIFACTS" || true

echo ">> Applying lifecycle policy..."
mc ilm import "$ALIAS/$MINIO_BUCKET_ARTIFACTS" < /etc/lifecycle.json || true

echo ">> Enabling default encryption (SSE-S3) on all buckets..."
for b in "$MINIO_BUCKET_ARTIFACTS" "$MINIO_BUCKET_LOGS" "$MINIO_BUCKET_TRACES"; do
  mc encrypt set sse-s3 "$ALIAS/$b" 2>/dev/null || true
done

echo ">> Creating service account for orchestrator (if access keys provided)..."
if [ -n "$MINIO_ACCESS_KEY" ] && [ -n "$MINIO_SECRET_KEY" ]; then
  mc admin user svcacct add "$ALIAS" "$MINIO_ROOT_USER" \
    --access-key "$MINIO_ACCESS_KEY" \
    --secret-key "$MINIO_SECRET_KEY" 2>/dev/null \
    || echo "   service account already exists"
else
  echo "   skipped — MINIO_ACCESS_KEY/SECRET_KEY empty in .env"
fi

echo "✓ MinIO bootstrap complete."
