#!/usr/bin/env bash
set -euo pipefail

SANDBOX="${NEMOCLAW_SANDBOX_NAME:-vanilla-agent}"
SHOW_TOKEN=0
LOCAL_PORT="${OPENCLAW_DASHBOARD_LOCAL_PORT:-18789}"
REMOTE_PORT="${OPENCLAW_DASHBOARD_REMOTE_PORT:-18789}"
GATEWAY_PORT="${OPENCLAW_DASHBOARD_GATEWAY_PORT:-18089}"
BIND_ADDR="${OPENCLAW_DASHBOARD_BIND_ADDR:-127.0.0.1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 [--sandbox NAME] [--show-token]

Starts and verifies a localhost OpenClaw dashboard forward.

Options:
  --sandbox NAME   NemoClaw sandbox name. Default: $SANDBOX
  --show-token     Also print the gateway token in this terminal.

Environment:
  OPENCLAW_DASHBOARD_LOCAL_PORT   Host localhost port. Default: $LOCAL_PORT
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sandbox)
      SANDBOX="${2:?missing sandbox name}"
      shift
      ;;
    --show-token)
      SHOW_TOKEN=1
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

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need nemoclaw
need docker
need python3
need curl

wait_for_dashboard() {
  local url="http://127.0.0.1:${LOCAL_PORT}/"
  local i

  for i in $(seq 1 20); do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  echo "Dashboard forward did not respond at $url" >&2
  return 1
}

gateway_container_ip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' openshell-cluster-nemoclaw
}

wait_for_gateway_forward() {
  local ip="$1"
  local url="http://${ip}:${GATEWAY_PORT}/"
  local i

  for i in $(seq 1 20); do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  echo "Gateway container port-forward did not respond at $url" >&2
  return 1
}

sandbox_exec() {
  docker exec openshell-cluster-nemoclaw \
    kubectl exec -n openshell "$SANDBOX" -c agent -- "$@"
}

sandbox_user_exec() {
  docker exec openshell-cluster-nemoclaw \
    kubectl exec -n openshell "$SANDBOX" -c agent -- \
    su -s /bin/bash -c "$1" sandbox
}

sandbox_dashboard_responds() {
  sandbox_exec curl -fsS --max-time 5 "http://127.0.0.1:${REMOTE_PORT}/" >/dev/null 2>&1
}

start_sandbox_dashboard() {
  echo "Starting OpenClaw gateway inside sandbox '$SANDBOX'"
  sandbox_user_exec \
    "nohup /usr/local/bin/openclaw gateway run --bind loopback --port ${REMOTE_PORT} >/tmp/openclaw-gateway-dashboard.log 2>&1 &"
}

ensure_sandbox_dashboard() {
  local i

  if sandbox_dashboard_responds; then
    return 0
  fi

  start_sandbox_dashboard
  for i in $(seq 1 30); do
    if sandbox_dashboard_responds; then
      return 0
    fi
    sleep 1
  done

  echo "OpenClaw dashboard is not responding inside sandbox '$SANDBOX'." >&2
  echo "Inspect the sandbox log with:" >&2
  echo "  docker exec openshell-cluster-nemoclaw kubectl exec -n openshell $SANDBOX -c agent -- su -s /bin/bash -c 'tail -80 /tmp/openclaw-gateway-dashboard.log' sandbox" >&2
  exit 1
}

start_gateway_port_forward() {
  docker exec openshell-cluster-nemoclaw \
    pkill -f "kubectl port-forward.*${SANDBOX}.*${GATEWAY_PORT}:${REMOTE_PORT}" \
    >/dev/null 2>&1 || true

  docker exec -d openshell-cluster-nemoclaw \
    kubectl port-forward -n openshell --address 0.0.0.0 \
    "pod/${SANDBOX}" "${GATEWAY_PORT}:${REMOTE_PORT}" >/dev/null
}

start_host_proxy() {
  local target_ip="$1"

  "$SCRIPT_DIR/stop-dashboard-forward.sh" "$SANDBOX" >/dev/null 2>&1 || true
  start_gateway_port_forward
  wait_for_gateway_forward "$target_ip"

  nohup python3 "$SCRIPT_DIR/dashboard_tcp_proxy.py" \
    --listen-host "$BIND_ADDR" \
    --listen-port "$LOCAL_PORT" \
    --target-host "$target_ip" \
    --target-port "$GATEWAY_PORT" \
    >/tmp/"${SANDBOX}-dashboard-proxy.log" 2>&1 &
}

echo "OpenClaw dashboard:"
if ! docker inspect openshell-cluster-nemoclaw >/dev/null 2>&1; then
  echo "OpenShell gateway container openshell-cluster-nemoclaw was not found." >&2
  exit 1
fi

if ! docker exec openshell-cluster-nemoclaw kubectl get pod -n openshell "$SANDBOX" >/dev/null 2>&1; then
  echo "Sandbox pod '$SANDBOX' was not found." >&2
  exit 1
fi

ensure_sandbox_dashboard

GATEWAY_IP="$(gateway_container_ip)"
start_host_proxy "$GATEWAY_IP"
wait_for_dashboard

cat <<EOF
Dashboard URL: http://127.0.0.1:${LOCAL_PORT}/
Forward: ${BIND_ADDR}:${LOCAL_PORT} -> ${SANDBOX}:127.0.0.1:${REMOTE_PORT}
Browser launch disabled (--no-open). Use the URL above on this host.

If your browser is on another machine, run this there first:
  ssh -N -L ${LOCAL_PORT}:127.0.0.1:${LOCAL_PORT} $(id -un)@$(hostname -I 2>/dev/null | awk '{print $1}')

Then open:
  http://127.0.0.1:${LOCAL_PORT}/
EOF

echo
if [ "$SHOW_TOKEN" -eq 1 ]; then
  echo "Gateway token:"
  nemoclaw "$SANDBOX" gateway-token --quiet
else
  cat <<EOF
Gateway token:
  nemoclaw $SANDBOX gateway-token --quiet

To print the token now:
  ./scripts/show-openclaw-dashboard.sh --sandbox $SANDBOX --show-token
EOF
fi
