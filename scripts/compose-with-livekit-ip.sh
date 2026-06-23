#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

detect_livekit_node_ip() {
  local primary_interface
  primary_interface="$(route get default 2>/dev/null | awk '/interface:/{print $2; exit}')"

  if [[ -n "${primary_interface}" ]]; then
    local detected_ip
    detected_ip="$(ipconfig getifaddr "${primary_interface}" 2>/dev/null || true)"
    if [[ -n "${detected_ip}" ]]; then
      printf '%s\n' "${detected_ip}"
      return 0
    fi
  fi

  ifconfig | awk '/inet / && $2 != "127.0.0.1" { print $2; exit }'
}

# 사용자가 명시적으로 값을 넘기지 않았다면 현재 호스트의 기본 네트워크 IPv4를 자동 사용한다.
LIVEKIT_NODE_IP="${LIVEKIT_NODE_IP:-$(detect_livekit_node_ip)}"

if [[ -z "${LIVEKIT_NODE_IP}" ]]; then
  echo "Unable to detect LIVEKIT_NODE_IP automatically." >&2
  echo "Set LIVEKIT_NODE_IP explicitly and retry." >&2
  exit 1
fi

echo "Using LIVEKIT_NODE_IP=${LIVEKIT_NODE_IP}"

cd "${INFRA_DIR}"
export LIVEKIT_NODE_IP
exec docker compose "$@"
