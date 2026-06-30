#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_DIR="${INFRA_DIR}/.runtime"

AWS_REGION="${AWS_REGION:?AWS_REGION is required}"
SSM_SHARED_PREFIX="${SSM_SHARED_PREFIX:-/meetbowl/prod/shared}"

mkdir -p "${RUNTIME_DIR}"

write_ssm_env_file() {
  local prefix="$1"
  local target_file="$2"

  : > "${target_file}"
  while IFS=$'\t' read -r name value; do
    if [[ -z "${name:-}" ]]; then
      continue
    fi
    local key="${name##*/}"
    printf '%s=%q\n' "${key}" "${value}" >> "${target_file}"
  done < <(
    aws ssm get-parameters-by-path \
      --path "${prefix}" \
      --recursive \
      --with-decryption \
      --query 'Parameters[*].[Name,Value]' \
      --output text
  )
}

write_ssm_env_file "${SSM_SHARED_PREFIX}" "${RUNTIME_DIR}/shared.env"

set -a
source "${RUNTIME_DIR}/shared.env"
set +a

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "required environment variable is missing after SSM load: ${key}" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "required file is missing: ${path}" >&2
    exit 1
  fi
}

for key in \
  LIVEKIT_API_KEY \
  LIVEKIT_API_SECRET \
  LIVEKIT_NODE_IP \
  NGINX_CERTS_DIR
do
  require_env "${key}"
done

require_file "${NGINX_CERTS_DIR}/fullchain.pem"
require_file "${NGINX_CERTS_DIR}/privkey.pem"

docker compose \
  -f "${INFRA_DIR}/livekit/compose.prod.yml" \
  config -q

docker compose \
  -f "${INFRA_DIR}/livekit/compose.prod.yml" \
  up -d

for _ in $(seq 1 30); do
  if curl -kfsS "https://127.0.0.1:${NGINX_HTTPS_PORT:-443}/healthz" >/dev/null \
    && bash -c "</dev/tcp/127.0.0.1/${LIVEKIT_HTTP_PORT:-7880}" 2>/dev/null; then
    exit 0
  fi
  sleep 2
done

echo "smoke test failed: livekit nginx or signaling port did not respond in time" >&2
exit 1
