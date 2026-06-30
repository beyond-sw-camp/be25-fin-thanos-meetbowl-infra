#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_DIR="${INFRA_DIR}/.runtime"

AWS_REGION="${AWS_REGION:?AWS_REGION is required}"
ECR_REPOSITORY="${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
IMAGE_TAG="${IMAGE_TAG:-}"
SSM_SHARED_PREFIX="${SSM_SHARED_PREFIX:-/meetbowl/prod/shared}"
SSM_BE_PREFIX="${SSM_BE_PREFIX:-/meetbowl/prod/be}"
SSM_BE_API_PREFIX="${SSM_BE_API_PREFIX:-/meetbowl/prod/be-api}"

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
write_ssm_env_file "${SSM_BE_PREFIX}" "${RUNTIME_DIR}/be.env"
write_ssm_env_file "${SSM_BE_API_PREFIX}" "${RUNTIME_DIR}/be-api.env"

set -a
source "${RUNTIME_DIR}/shared.env"
source "${RUNTIME_DIR}/be.env"
source "${RUNTIME_DIR}/be-api.env"
set +a

derive_rabbitmq_connection_env() {
  if [[ -z "${MEETBOWL_RABBITMQ_URI:-}" ]]; then
    return 0
  fi

  local uri scheme remainder authority path userinfo hostport username password host port
  uri="${MEETBOWL_RABBITMQ_URI}"
  scheme="${uri%%://*}"
  remainder="${uri#*://}"
  authority="${remainder%%/*}"
  path=""
  if [[ "${remainder}" == */* ]]; then
    path="/${remainder#*/}"
  fi

  userinfo="${authority%@*}"
  hostport="${authority##*@}"
  if [[ "${authority}" == "${hostport}" ]]; then
    userinfo=""
  fi

  host="${hostport%:*}"
  port="${hostport##*:}"
  if [[ "${host}" == "${port}" ]]; then
    port=""
  fi

  if [[ -n "${userinfo}" ]]; then
    username="${userinfo%%:*}"
    password="${userinfo#*:}"
    if [[ "${username}" != "${userinfo}" ]]; then
      export MEETBOWL_RABBITMQ_USERNAME="${username}"
      export MEETBOWL_RABBITMQ_PASSWORD="${password}"
    else
      export MEETBOWL_RABBITMQ_USERNAME="${userinfo}"
    fi
  fi

  export MEETBOWL_RABBITMQ_HOST="${host}"
  if [[ -n "${port}" ]]; then
    export MEETBOWL_RABBITMQ_PORT="${port}"
  fi
  if [[ -n "${path}" && "${path}" != "/" ]]; then
    export MEETBOWL_RABBITMQ_VHOST="${path}"
  else
    export MEETBOWL_RABBITMQ_VHOST="/"
  fi
  if [[ "${scheme}" == "amqps" ]]; then
    export MEETBOWL_RABBITMQ_SSL_ENABLED="true"
  else
    export MEETBOWL_RABBITMQ_SSL_ENABLED="false"
  fi
}

derive_rabbitmq_connection_env

IMAGE_TAG="${IMAGE_TAG:-${MEETBOWL_BE_IMAGE_TAG:-}}"

if [[ -z "${IMAGE_TAG}" ]]; then
  echo "required environment variable is missing: IMAGE_TAG or MEETBOWL_BE_IMAGE_TAG" >&2
  exit 1
fi

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
  MEETBOWL_DB_URL \
  MEETBOWL_DB_USERNAME \
  MEETBOWL_DB_PASSWORD \
  MEETBOWL_JWT_SECRET \
  MEETBOWL_INTERNAL_TOKEN \
  MEETBOWL_CORS_ALLOWED_ORIGIN_PATTERNS \
  MEETBOWL_LIVEKIT_URL \
  MEETBOWL_STT_BASE_URL \
  MEETBOWL_AI_BASE_URL \
  S3_BUCKET
do
  require_env "${key}"
done

check_http_endpoint() {
  local path="$1"

  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${NGINX_HTTP_PORT:-80}${path}" >/dev/null; then
      return 0
    fi
    sleep 2
  done

  echo "smoke test failed: ${path} did not respond in time" >&2
  return 1
}

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
MEETBOWL_BE_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
export MEETBOWL_BE_IMAGE

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

docker compose \
  -f "${INFRA_DIR}/shared/compose.api.prod.yml" \
  -f "${INFRA_DIR}/be-api/compose.prod.yml" \
  config -q

docker compose \
  -f "${INFRA_DIR}/shared/compose.api.prod.yml" \
  -f "${INFRA_DIR}/be-api/compose.prod.yml" \
  pull be

docker compose \
  -f "${INFRA_DIR}/shared/compose.api.prod.yml" \
  -f "${INFRA_DIR}/be-api/compose.prod.yml" \
  up -d nginx be

docker compose \
  -f "${INFRA_DIR}/shared/compose.api.prod.yml" \
  -f "${INFRA_DIR}/be-api/compose.prod.yml" \
  exec -T nginx nginx -t

docker compose \
  -f "${INFRA_DIR}/shared/compose.api.prod.yml" \
  -f "${INFRA_DIR}/be-api/compose.prod.yml" \
  exec -T nginx nginx -s reload

check_http_endpoint "/healthz"
check_http_endpoint "/api/v1/health"

exit 0
