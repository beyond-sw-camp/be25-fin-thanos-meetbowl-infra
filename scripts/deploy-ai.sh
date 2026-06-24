#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_DIR="${INFRA_DIR}/.runtime"

AWS_REGION="${AWS_REGION:?AWS_REGION is required}"
ECR_REPOSITORY="${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG is required}"
SSM_SHARED_PREFIX="${SSM_SHARED_PREFIX:-/meetbowl/prod/shared}"
SSM_AI_PREFIX="${SSM_AI_PREFIX:-/meetbowl/prod/ai}"

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
write_ssm_env_file "${SSM_AI_PREFIX}" "${RUNTIME_DIR}/ai.env"

set -a
source "${RUNTIME_DIR}/shared.env"
source "${RUNTIME_DIR}/ai.env"
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
  BE_BASE_URL \
  GEMINI_API_KEY \
  OPENAI_API_KEY \
  RABBITMQ_URL \
  REDIS_URL \
  QDRANT_URL \
  S3_BUCKET \
  AWS_REGION
do
  require_env "${key}"
done

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
MEETBOWL_AI_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
export MEETBOWL_AI_IMAGE

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

docker compose \
  -f "${INFRA_DIR}/shared/compose.prod.yml" \
  -f "${INFRA_DIR}/ai/compose.prod.yml" \
  config -q

docker compose \
  -f "${INFRA_DIR}/shared/compose.prod.yml" \
  -f "${INFRA_DIR}/ai/compose.prod.yml" \
  pull ai

docker compose \
  -f "${INFRA_DIR}/shared/compose.prod.yml" \
  -f "${INFRA_DIR}/ai/compose.prod.yml" \
  up -d ai

AI_PORT="${MEETBOWL_AI_PORT:-8000}"

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${AI_PORT}/api/v1/health/ready" >/dev/null; then
    exit 0
  fi
  sleep 2
done

echo "smoke test failed: ai readiness endpoint did not respond in time" >&2
exit 1
