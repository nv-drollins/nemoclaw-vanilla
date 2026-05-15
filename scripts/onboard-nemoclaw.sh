#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROVIDER="${NEMOCLAW_PROVIDER:-ollama}"
SANDBOX="${NEMOCLAW_SANDBOX_NAME:-vanilla-agent}"
DEFAULT_OLLAMA_MODEL="qwen3.6:35b"
MODEL="${NEMOCLAW_MODEL:-}"
MODEL_EXPLICIT=0
if [ -n "$MODEL" ]; then
  MODEL_EXPLICIT=1
fi
INSTALL_FRESH="${NEMOCLAW_INSTALL_FRESH:-1}"
ROUTER_BYPASS="${NEMOCLAW_ROUTER_BYPASS:-1}"
STRICT_MODEL_PULL="${NEMOCLAW_STRICT_MODEL_PULL:-1}"
WRAPPER_DIR="$(mktemp -d)"

set_default_model_for_provider() {
  if [ "$MODEL_EXPLICIT" -eq 1 ]; then
    return 0
  fi

  if [ "$PROVIDER" = "ollama" ]; then
    MODEL="$DEFAULT_OLLAMA_MODEL"
  else
    MODEL=""
  fi
}

set_default_model_for_provider

usage() {
  cat <<EOF
Usage: $0 [--sandbox NAME] [--model MODEL] [--provider PROVIDER] [--no-fresh]

Installs a vanilla NemoClaw/OpenClaw sandbox using the official installer.

Defaults:
  sandbox:  $SANDBOX
  provider: $PROVIDER
  model:    ${MODEL:-provider default}

Environment:
  NEMOCLAW_SANDBOX_NAME     Sandbox name. Default: vanilla-agent
  NEMOCLAW_PROVIDER         Provider. Default: ollama
  NEMOCLAW_MODEL            Model. Default for Ollama: qwen3.6:35b
  NEMOCLAW_ROUTER_BYPASS    Skip optional router pip install for non-routed providers. Default: 1
  NEMOCLAW_STRICT_MODEL_PULL Redirect unexpected ollama pulls to NEMOCLAW_MODEL. Default: 1
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sandbox)
      SANDBOX="${2:?missing sandbox name}"
      shift
      ;;
    --model)
      MODEL="${2:?missing model}"
      MODEL_EXPLICIT=1
      shift
      ;;
    --provider)
      PROVIDER="${2:?missing provider}"
      set_default_model_for_provider
      shift
      ;;
    --no-fresh)
      INSTALL_FRESH=0
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

if [ "$MODEL_EXPLICIT" -eq 0 ]; then
  set_default_model_for_provider
fi

drop_path_entry() {
  local remove="$1"
  local entry new_path=""

  IFS=: read -r -a entries <<<"$PATH"
  for entry in "${entries[@]}"; do
    if [ "$entry" = "$remove" ]; then
      continue
    fi

    if [ -z "$new_path" ]; then
      new_path="$entry"
    else
      new_path="$new_path:$entry"
    fi
  done

  printf '%s\n' "$new_path"
}

cleanup() {
  rm -rf "$WRAPPER_DIR"
}
trap cleanup EXIT

if [ -n "${VIRTUAL_ENV:-}" ]; then
  echo "Ignoring active Python virtualenv during NemoClaw install: $VIRTUAL_ENV"
  PATH="$(drop_path_entry "$VIRTUAL_ENV/bin")"
  export PATH
  unset VIRTUAL_ENV
fi
unset PIP_REQUIRE_VIRTUALENV PYTHONHOME PYTHONPATH

REAL_OLLAMA_BIN="${NEMOCLAW_OLLAMA_BIN:-}"
if [ -z "$REAL_OLLAMA_BIN" ]; then
  REAL_OLLAMA_BIN="$(command -v ollama 2>/dev/null || true)"
fi

REAL_PIP_BIN="${NEMOCLAW_PIP_BIN:-}"
if [ -z "$REAL_PIP_BIN" ]; then
  REAL_PIP_BIN="$(command -v pip3 2>/dev/null || command -v pip 2>/dev/null || true)"
fi

export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
export NEMOCLAW_PROVIDER="$PROVIDER"
if [ -n "$MODEL" ]; then
  export NEMOCLAW_MODEL="$MODEL"
fi
export NEMOCLAW_SANDBOX_NAME="$SANDBOX"
export NEMOCLAW_POLICY_TIER="${NEMOCLAW_POLICY_TIER:-balanced}"
export NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1
export NEMOCLAW_NON_INTERACTIVE=1
export NEMOCLAW_YES="${NEMOCLAW_YES:-1}"
export NEMOCLAW_LOCAL_INFERENCE_TIMEOUT="${NEMOCLAW_LOCAL_INFERENCE_TIMEOUT:-300}"
export NEMOCLAW_SANDBOX_READY_TIMEOUT="${NEMOCLAW_SANDBOX_READY_TIMEOUT:-600}"
export NEMOCLAW_ROUTER_BYPASS="$ROUTER_BYPASS"
export NEMOCLAW_STRICT_MODEL_PULL="$STRICT_MODEL_PULL"
if [ -n "$REAL_OLLAMA_BIN" ]; then
  export NEMOCLAW_OLLAMA_BIN="$REAL_OLLAMA_BIN"
fi
if [ -n "$REAL_PIP_BIN" ]; then
  export NEMOCLAW_REAL_PIP_BIN="$REAL_PIP_BIN"
fi

ensure_nvidia_cdi_specs() {
  if ! command -v nvidia-ctk >/dev/null 2>&1; then
    return 0
  fi

  if nvidia-ctk cdi list 2>/dev/null | grep -q 'nvidia.com/gpu=all'; then
    return 0
  fi

  echo "Generating NVIDIA CDI specs for OpenShell GPU passthrough"
  sudo mkdir -p /etc/cdi
  sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

  if ! nvidia-ctk cdi list 2>/dev/null | grep -q 'nvidia.com/gpu=all'; then
    echo "NVIDIA CDI specs were not generated correctly; run 'nvidia-ctk cdi list' for details." >&2
    exit 1
  fi
}

cat >"$WRAPPER_DIR/ollama" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

find_real_ollama() {
  local self candidate resolved
  self="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"

  if [ -n "${NEMOCLAW_OLLAMA_BIN:-}" ] && [ -x "$NEMOCLAW_OLLAMA_BIN" ]; then
    resolved="$(readlink -f "$NEMOCLAW_OLLAMA_BIN" 2>/dev/null || printf '%s' "$NEMOCLAW_OLLAMA_BIN")"
    if [ "$resolved" != "$self" ]; then
      printf '%s\n' "$NEMOCLAW_OLLAMA_BIN"
      return 0
    fi
  fi

  for candidate in /usr/local/bin/ollama /usr/bin/ollama /bin/ollama; do
    if [ -x "$candidate" ]; then
      resolved="$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")"
      if [ "$resolved" != "$self" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  done

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    resolved="$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")"
    if [ "$resolved" != "$self" ] && [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(type -P -a ollama 2>/dev/null | awk '!seen[$0]++')
}

desired_model="${NEMOCLAW_MODEL:-}"
if [ "${NEMOCLAW_PROVIDER:-ollama}" = "ollama" ] &&
   [ "${NEMOCLAW_STRICT_MODEL_PULL:-1}" = "1" ] &&
   [ "$#" -ge 2 ] &&
   [ "$1" = "pull" ] &&
   [ -n "$desired_model" ] &&
   [ "$2" != "$desired_model" ]; then
  requested_model="$2"
  echo "Redirecting NemoClaw installer model pull from $requested_model to $desired_model" >&2
  shift 2
  set -- pull "$desired_model" "$@"
fi

real_ollama="$(find_real_ollama || true)"
if [ -z "$real_ollama" ]; then
  echo "real ollama binary not found yet" >&2
  exit 127
fi

exec "$real_ollama" "$@"
EOF
chmod +x "$WRAPPER_DIR/ollama"

cat >"$WRAPPER_DIR/pip3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

find_real_pip() {
  local self candidate resolved
  self="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"

  if [ -n "${NEMOCLAW_REAL_PIP_BIN:-}" ] && [ -x "$NEMOCLAW_REAL_PIP_BIN" ]; then
    resolved="$(readlink -f "$NEMOCLAW_REAL_PIP_BIN" 2>/dev/null || printf '%s' "$NEMOCLAW_REAL_PIP_BIN")"
    if [ "$resolved" != "$self" ]; then
      printf '%s\n' "$NEMOCLAW_REAL_PIP_BIN"
      return 0
    fi
  fi

  for candidate in /usr/local/bin/pip3 /usr/bin/pip3 /bin/pip3 /usr/local/bin/pip /usr/bin/pip /bin/pip; do
    if [ -x "$candidate" ]; then
      resolved="$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")"
      if [ "$resolved" != "$self" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  done
}

should_skip_model_router_install() {
  local arg saw_install=0 saw_user=0 saw_router=0

  [ "${NEMOCLAW_ROUTER_BYPASS:-1}" = "1" ] || return 1
  [ "${NEMOCLAW_PROVIDER:-}" != "routed" ] || return 1

  for arg in "$@"; do
    [ "$arg" = "install" ] && saw_install=1
    [ "$arg" = "--user" ] && saw_user=1
    case "$arg" in
      *llm-router*|*model-router*|*\[prefill,proxy\]*) saw_router=1 ;;
    esac
  done

  [ "$saw_install" -eq 1 ] && [ "$saw_user" -eq 1 ] && [ "$saw_router" -eq 1 ]
}

if should_skip_model_router_install "$@"; then
  echo "Skipping optional NemoClaw model router install for provider '${NEMOCLAW_PROVIDER:-}'" >&2
  exit 0
fi

real_pip="$(find_real_pip || true)"
if [ -z "$real_pip" ]; then
  echo "real pip binary not found" >&2
  exit 127
fi

exec "$real_pip" "$@"
EOF
chmod +x "$WRAPPER_DIR/pip3"
cp "$WRAPPER_DIR/pip3" "$WRAPPER_DIR/pip"

export PATH="$WRAPPER_DIR:$PATH"

bash "$SCRIPT_DIR/ensure-sudo.sh"
ensure_nvidia_cdi_specs

install_args=(--non-interactive --yes-i-accept-third-party-software)
if [ "$INSTALL_FRESH" = "1" ]; then
  install_args+=(--fresh)
fi

echo "Onboarding sandbox '$SANDBOX'"
echo "Provider: $PROVIDER"
echo "Model:    ${MODEL:-provider default}"
echo

curl -fsSL https://www.nvidia.com/nemoclaw.sh -o /tmp/nemoclaw.sh
bash /tmp/nemoclaw.sh "${install_args[@]}"

echo
echo "NemoClaw onboarding finished."
if command -v nemoclaw >/dev/null 2>&1; then
  nemoclaw "$SANDBOX" status || true
fi
