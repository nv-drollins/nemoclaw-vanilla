#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="${1:-${NEMOCLAW_SANDBOX_NAME:-vanilla-agent}}"

export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

if ! command -v docker >/dev/null 2>&1; then
  echo "Missing docker; cannot prepare in-sandbox OpenClaw inference route." >&2
  exit 1
fi

direct_sandbox_container() {
  docker ps --filter "name=openshell-${SANDBOX}-" --format '{{.Names}}' | head -n 1
}

if docker inspect openshell-cluster-nemoclaw >/dev/null 2>&1; then
  docker exec -i openshell-cluster-nemoclaw \
    kubectl exec -i -n openshell "$SANDBOX" -c agent -- \
    runuser -u sandbox -- bash -s < "$SCRIPT_DIR/sandbox-node-inference-setup.sh"
  exit 0
fi

CONTAINER="$(direct_sandbox_container)"
if [ -z "$CONTAINER" ]; then
  echo "OpenShell sandbox container for '$SANDBOX' was not found." >&2
  exit 1
fi

docker exec -i "$CONTAINER" \
  runuser -u sandbox -- bash -s < "$SCRIPT_DIR/sandbox-node-inference-setup.sh"
