#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="${1:-${NEMOCLAW_SANDBOX_NAME:-vanilla-agent}}"
LOCAL_PORT="${OPENCLAW_DASHBOARD_LOCAL_PORT:-18789}"
GATEWAY_PORT="${OPENCLAW_DASHBOARD_GATEWAY_PORT:-18089}"

stop_host_processes() {
  local pids

  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -tiTCP:"$LOCAL_PORT" -sTCP:LISTEN 2>/dev/null || true)"
    if [ -n "$pids" ]; then
      # shellcheck disable=SC2086
      kill $pids 2>/dev/null || true
    fi
  elif command -v fuser >/dev/null 2>&1; then
    fuser -k "${LOCAL_PORT}/tcp" >/dev/null 2>&1 || true
  fi

  pids="$(
    ps -eo pid=,args= |
      awk -v script="$SCRIPT_DIR/dashboard_tcp_proxy.py" -v port="$LOCAL_PORT" '
        $0 ~ script && $0 ~ ("--listen-port " port) { print $1 }
      '
  )"
  if [ -n "$pids" ]; then
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
  fi

  pids="$(
    ps -eo pid=,args= |
      awk -v host="openshell-${SANDBOX}" -v port="$LOCAL_PORT" '
        $0 ~ /ssh/ && $0 ~ host && $0 ~ "-L" && $0 ~ port { print $1 }
      '
  )"
  if [ -n "$pids" ]; then
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
  fi

  pids="$(
    ps -eo pid=,args= |
      awk -v sandbox="$SANDBOX" -v port="$LOCAL_PORT" '
        $0 ~ /openshell forward service/ && $0 ~ sandbox && $0 ~ port { print $1 }
      '
  )"
  if [ -n "$pids" ]; then
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
  fi
}

stop_gateway_port_forward() {
  if ! command -v docker >/dev/null 2>&1; then
    return 0
  fi
  if ! docker inspect openshell-cluster-nemoclaw >/dev/null 2>&1; then
    return 0
  fi

  docker exec openshell-cluster-nemoclaw \
    pkill -f "kubectl port-forward.*${SANDBOX}.*${GATEWAY_PORT}:18789" \
    >/dev/null 2>&1 || true
}

stop_host_processes
stop_gateway_port_forward

if command -v openshell >/dev/null 2>&1; then
  openshell forward stop "$LOCAL_PORT" >/dev/null 2>&1 || true
fi

echo "Dashboard forward stopped for sandbox $SANDBOX."
