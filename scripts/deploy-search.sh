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

docker compose \
  -f "${INFRA_DIR}/search/compose.prod.yml" \
  config -q

docker compose \
  -f "${INFRA_DIR}/search/compose.prod.yml" \
  up -d

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${ELASTICSEARCH_HTTP_PORT:-9200}" >/dev/null \
    && curl -fsS "http://127.0.0.1:${QDRANT_HTTP_PORT:-6333}" >/dev/null; then
    exit 0
  fi
  sleep 2
done

echo "smoke test failed: search services did not respond in time" >&2
exit 1
