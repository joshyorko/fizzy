#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

if [[ $# -gt 0 ]]; then
  REPO_INPUT="$1"
else
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  REPO_INPUT="${remote_url#git@github.com:}"
  REPO_INPUT="${REPO_INPUT#https://github.com/}"
  REPO_INPUT="${REPO_INPUT%.git}"
fi

REPO="$(gh repo view "$REPO_INPUT" --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || printf '%s' "$REPO_INPUT")"
ENV_FILE="${ENV_FILE:-.env.kamal.local}"
MASTER_KEY_FILE="${MASTER_KEY_FILE:-config/master.key}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

allowed_keys=(
  KAMAL_SERVER_ALIAS
  KAMAL_PUBLIC_HOST
  KAMAL_SSH_USER
  KAMAL_STORAGE_PATH
  KAMAL_MAILER_FROM_ADDRESS
  KAMAL_KNOWN_HOST
  S3_ENDPOINT
  S3_BUCKET
  S3_REGION
  S3_FORCE_PATH_STYLE
  S3_BUCKET_SETUP_ENABLED
  SECRET_KEY_BASE
  VAPID_PUBLIC_KEY
  VAPID_PRIVATE_KEY
  SMTP_USERNAME
  SMTP_PASSWORD
  S3_ACCESS_KEY_ID
  S3_SECRET_ACCESS_KEY
  CLOUDFLARED_TOKEN
)

while IFS='=' read -r key value; do
  [[ -z "${key}" ]] && continue
  [[ "${key}" =~ ^[[:space:]]*# ]] && continue

  if [[ ! " ${allowed_keys[*]} " =~ (^|[[:space:]])${key}($|[[:space:]]) ]]; then
    continue
  fi

  secret_value="${value}"
  if [[ "${secret_value}" =~ ^\".*\"$ ]]; then
    secret_value="${secret_value:1:-1}"
  fi

  printf '%s' "$secret_value" | gh secret set "$key" --repo "$REPO"
  echo "synced $key"
done < <(grep -E '^[A-Z0-9_]+=' "$ENV_FILE")

if [[ -f "$MASTER_KEY_FILE" ]]; then
  gh secret set RAILS_MASTER_KEY --repo "$REPO" < "$MASTER_KEY_FILE"
  echo "synced RAILS_MASTER_KEY"
else
  echo "warning: $MASTER_KEY_FILE not found; skipping RAILS_MASTER_KEY" >&2
fi

registry_password="${KAMAL_REGISTRY_PASSWORD:-}"
if [[ -z "$registry_password" ]] && gh auth token >/dev/null 2>&1; then
  registry_password="$(gh auth token)"
fi

if [[ -n "$registry_password" ]]; then
  printf '%s' "$registry_password" | gh secret set KAMAL_REGISTRY_PASSWORD --repo "$REPO"
  echo "synced KAMAL_REGISTRY_PASSWORD"
else
  echo "warning: KAMAL_REGISTRY_PASSWORD not available; skipping registry secret" >&2
fi
