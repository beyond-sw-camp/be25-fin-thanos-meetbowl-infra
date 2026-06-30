#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rollback_to_all_mode() {
  echo "split deploy failed, rolling back to all mode" >&2
  "${SCRIPT_DIR}/deploy-be.sh"
}

if ! "${SCRIPT_DIR}/deploy-be-api.sh"; then
  rollback_to_all_mode
  exit 1
fi

if ! "${SCRIPT_DIR}/deploy-be-worker.sh"; then
  rollback_to_all_mode
  exit 1
fi
