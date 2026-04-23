#!/usr/bin/env sh
set -eu

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: DATABASE_URL is required (Railway Postgres connection string)." >&2
  exit 1
fi

if [ -z "${R2_BUCKET:-}" ]; then
  echo "ERROR: R2_BUCKET is required (Cloudflare R2 bucket name)." >&2
  exit 1
fi

if [ -z "${MLFLOW_S3_ENDPOINT_URL:-}" ]; then
  echo "ERROR: MLFLOW_S3_ENDPOINT_URL is required (Cloudflare R2 S3 endpoint URL)." >&2
  exit 1
fi

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "ERROR: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are required (R2 access keys)." >&2
  exit 1
fi

if [ -z "${PORT:-}" ]; then
  echo "ERROR: PORT is required (Railway injects this automatically)." >&2
  exit 1
fi

if [ -z "${BASIC_AUTH_USER:-}" ] || [ -z "${BASIC_AUTH_PASSWORD:-}" ]; then
  echo "ERROR: BASIC_AUTH_USER and BASIC_AUTH_PASSWORD are required." >&2
  exit 1
fi

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"
export AWS_EC2_METADATA_DISABLED="${AWS_EC2_METADATA_DISABLED:-true}"

MLFLOW_INTERNAL_HOST="${MLFLOW_INTERNAL_HOST:-127.0.0.1}"
MLFLOW_INTERNAL_PORT="${MLFLOW_INTERNAL_PORT:-5000}"

ARTIFACT_PREFIX="${R2_ARTIFACT_PREFIX:-mlflow}"
DEFAULT_ARTIFACT_ROOT="s3://${R2_BUCKET}/${ARTIFACT_PREFIX}"

if [ -z "${BASIC_AUTH_PASSWORD_HASH:-}" ]; then
  BASIC_AUTH_PASSWORD_HASH="$(caddy hash-password --plaintext "${BASIC_AUTH_PASSWORD}")"
  export BASIC_AUTH_PASSWORD_HASH
fi

# Explicit exports so Caddy always inherits them (even if provided non-exported).
export PORT BASIC_AUTH_USER

# Reduce exposure of plaintext password in process environment.
unset BASIC_AUTH_PASSWORD

echo "Starting MLflow server..."
mlflow server \
  --backend-store-uri "${DATABASE_URL}" \
  --default-artifact-root "${DEFAULT_ARTIFACT_ROOT}" \
  --host "${MLFLOW_INTERNAL_HOST}" \
  --port "${MLFLOW_INTERNAL_PORT}" \
  --gunicorn-opts "--access-logfile - --error-logfile - --workers ${MLFLOW_WORKERS:-2}" &

MLFLOW_PID="$!"

cleanup() {
  if kill -0 "${MLFLOW_PID}" 2>/dev/null; then
    kill "${MLFLOW_PID}" 2>/dev/null || true
  fi
}
trap cleanup INT TERM

echo "Starting Caddy reverse proxy on :${PORT}..."
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile

