#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="${NEMOCLAW_SANDBOX_NAME:-vanilla-agent}"
DESTROY=0

usage() {
  cat <<EOF
Usage: $0 [--sandbox NAME] [--destroy]

Stops the dashboard forward and stops the NemoClaw sandbox.

Options:
  --sandbox NAME   Sandbox name. Default: $SANDBOX
  --destroy        Destroy the sandbox instead of stopping it.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sandbox)
      SANDBOX="${2:?missing sandbox name}"
      shift
      ;;
    --destroy)
      DESTROY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

"$SCRIPT_DIR/stop-dashboard-forward.sh" "$SANDBOX" >/dev/null 2>&1 || true

if ! command -v nemoclaw >/dev/null 2>&1; then
  echo "nemoclaw command not found; dashboard forward was stopped."
  exit 0
fi

if [ "$DESTROY" -eq 1 ]; then
  echo "Destroying sandbox '$SANDBOX'"
  nemoclaw "$SANDBOX" destroy --yes --force || true
else
  echo "Stopping sandbox '$SANDBOX'"
  nemoclaw "$SANDBOX" stop || true
fi

echo "Done."

