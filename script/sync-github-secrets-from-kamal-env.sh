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
DRY_RUN="${DRY_RUN:-0}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

set_secret() {
  local key="$1"
  local value="$2"

  if [[ -z "$value" ]]; then
    echo "Refusing to sync empty value for $key" >&2
    exit 1
  fi

  if [[ "$DRY_RUN" = "1" ]]; then
    echo "would sync $key (${#value} bytes)"
  else
    gh secret set "$key" --repo "$REPO" --body "$value"
    echo "synced $key"
  fi
}

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

required_keys=(
  KAMAL_SERVER_ALIAS
  KAMAL_PUBLIC_HOST
  KAMAL_SSH_USER
  KAMAL_STORAGE_PATH
  KAMAL_MAILER_FROM_ADDRESS
  KAMAL_KNOWN_HOST
  S3_ENDPOINT
  S3_BUCKET
  SECRET_KEY_BASE
  VAPID_PUBLIC_KEY
  VAPID_PRIVATE_KEY
  SMTP_USERNAME
  SMTP_PASSWORD
  S3_ACCESS_KEY_ID
  S3_SECRET_ACCESS_KEY
  CLOUDFLARED_TOKEN
)

declare -A secret_values=()

while IFS='=' read -r key value; do
  [[ -z "${key}" ]] && continue
  [[ "${key}" =~ ^[[:space:]]*# ]] && continue

  if [[ ! " ${allowed_keys[*]} " =~ (^|[[:space:]])${key}($|[[:space:]]) ]]; then
    continue
  fi

  secret_value="${value}"
  if [[ "${secret_value}" =~ ^\".*\"$ ]]; then
    secret_value="${secret_value:1:-1}"
  elif [[ "${secret_value}" =~ ^\'.*\'$ ]]; then
    secret_value="${secret_value:1:-1}"
  fi
  secret_value="${secret_value%$'\r'}"

  secret_values["$key"]="$secret_value"
done < <(grep -E '^[A-Z0-9_]+=' "$ENV_FILE")

missing_keys=()
for key in "${required_keys[@]}"; do
  if [[ -z "${secret_values[$key]:-}" ]]; then
    missing_keys+=("$key")
  fi
done

if [[ "${#missing_keys[@]}" -gt 0 ]]; then
  echo "Refusing to update GitHub secrets because $ENV_FILE is missing required values:" >&2
  printf '  %s\n' "${missing_keys[@]}" >&2
  exit 1
fi

for key in "${allowed_keys[@]}"; do
  secret_value="${secret_values[$key]:-}"
  if [[ -z "$secret_value" ]]; then
    echo "skipped $key (not set in $ENV_FILE)"
    continue
  fi

  set_secret "$key" "$secret_value"
done

if [[ -s "$MASTER_KEY_FILE" ]]; then
  master_key="$(< "$MASTER_KEY_FILE")"
  set_secret RAILS_MASTER_KEY "$master_key"
else
  echo "warning: $MASTER_KEY_FILE not found or empty; skipping RAILS_MASTER_KEY" >&2
fi

registry_password="${KAMAL_REGISTRY_PASSWORD:-}"
if [[ -z "$registry_password" ]] && gh auth token >/dev/null 2>&1; then
  registry_password="$(gh auth token)"
fi

if [[ -n "$registry_password" ]]; then
  set_secret KAMAL_REGISTRY_PASSWORD "$registry_password"
else
  echo "warning: KAMAL_REGISTRY_PASSWORD not available; skipping registry secret" >&2
fi
