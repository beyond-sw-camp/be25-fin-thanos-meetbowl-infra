#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_DIR="${INFRA_DIR}/.runtime"

AWS_REGION="${AWS_REGION:?AWS_REGION is required}"
ECR_REPOSITORY="${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG is required}"
SSM_SHARED_PREFIX="${SSM_SHARED_PREFIX:-/meetbowl/prod/shared}"
SSM_STT_PREFIX="${SSM_STT_PREFIX:-/meetbowl/prod/stt}"

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
write_ssm_env_file "${SSM_STT_PREFIX}" "${RUNTIME_DIR}/stt.env"

set -a
source "${RUNTIME_DIR}/shared.env"
source "${RUNTIME_DIR}/stt.env"
set +a

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "required environment variable is missing after SSM load: ${key}" >&2
    exit 1
  fi
}

for key in \
  INTERNAL_TOKEN \
  OPENAI_API_KEY \
  LIVEKIT_API_KEY \
  LIVEKIT_API_SECRET \
  RABBITMQ_URL \
  REDIS_URL
do
  require_env "${key}"
done

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
MEETBOWL_STT_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
export MEETBOWL_STT_IMAGE

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

docker compose \
  -f "${INFRA_DIR}/shared/compose.prod.yml" \
  -f "${INFRA_DIR}/stt/compose.prod.yml" \
  config -q

docker compose \
  -f "${INFRA_DIR}/shared/compose.prod.yml" \
  -f "${INFRA_DIR}/stt/compose.prod.yml" \
  pull stt

docker compose \
  -f "${INFRA_DIR}/shared/compose.prod.yml" \
  -f "${INFRA_DIR}/stt/compose.prod.yml" \
  up -d stt

STT_PORT="${MEETBOWL_STT_PORT:-3000}"

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${STT_PORT}/api/v1/health" >/dev/null \
    && curl -fsS "http://127.0.0.1:${STT_PORT}/api/v1/health/provider" >/dev/null; then
    exit 0
  fi
  sleep 2
done

echo "smoke test failed: stt health endpoints did not respond in time" >&2
exit 1
