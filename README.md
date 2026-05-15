# Vanilla NemoClaw with Local Ollama

This repo installs a plain NemoClaw/OpenClaw sandbox that uses local Ollama inference by default.

It also includes the small router bypass we needed on DGX Spark: when the selected provider is not `routed`, the installer skips the optional `llm-router` pip install that can fail in externally managed Python environments or active virtualenvs.

Default model:

```bash
qwen3.6:35b
```

## Sudo Prompts

First-time setup may need sudo for host packages, Docker/NVIDIA toolkit configuration, or setup preflight checks. Passwordless sudo is not required, but install commands must run from an interactive terminal so sudo can prompt. When installing over SSH, use:

```bash
ssh -t nvidia@<spark-ip>
```

## Before You Begin

Run this on the Linux host where NemoClaw should run. The host should already have:

- Docker
- NVIDIA Container Toolkit
- NVIDIA drivers and `nvidia-ctk`
- `curl`
- `sudo` access
- enough GPU memory for the selected Ollama model

### Enable Docker access without sudo

DGX Spark systems may not add the current user to the `docker` group by
default. If you skip this step, run Docker commands with `sudo`.

Open a new terminal and test Docker access:

```bash
docker ps
```

If you see a permission denied error while connecting to the Docker daemon
socket, add your user to the `docker` group:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

`newgrp docker` updates group membership for the current shell. You can also
log out and back in, then rerun `docker ps`.

### Configure Docker GPU runtime

DGX Spark systems may include the NVIDIA Container Toolkit out of the box, but
Docker still needs the NVIDIA runtime configured:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Optional verification:

```bash
sudo docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

### Install and expose Ollama

If you use the default `NEMOCLAW_PROVIDER=ollama` path, the NemoClaw sandbox
must be able to reach the host Ollama server. Install Ollama on the host, then
configure the systemd service to listen on all interfaces. **Important for DGX
Spark / GB10: pin Ollama to `0.22.1`; newer `0.23.x` builds have been observed
to fall back to CPU-only execution on GB10.**

```bash
OLLAMA_VERSION=0.22.1
OLLAMA_ARCH="$(case "$(uname -m)" in aarch64|arm64) echo arm64 ;; x86_64|amd64) echo amd64 ;; *) uname -m ;; esac)"
curl -fL --show-error -o "/tmp/ollama-linux-${OLLAMA_ARCH}.tar.zst" \
  "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-${OLLAMA_ARCH}.tar.zst"
sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama 2>/dev/null || true
sudo usermod -a -G video,render ollama 2>/dev/null || true
sudo tar --zstd -xf "/tmp/ollama-linux-${OLLAMA_ARCH}.tar.zst" -C /usr/local
sudo chmod -R a+rX /usr/local/lib/ollama
sudo tee /etc/systemd/system/ollama.service >/dev/null <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=default.target
EOF

sudo mkdir -p /etc/systemd/system/ollama.service.d
printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0"\n' | sudo tee /etc/systemd/system/ollama.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

Verify Ollama is running:

```bash
curl http://0.0.0.0:11434
```

Expected response:

```text
Ollama is running
```

If it is not running, start it with:

```bash
sudo systemctl start ollama
```

Always start Ollama through systemd with `sudo systemctl restart ollama` or
`sudo systemctl start ollama`. Do not use `ollama serve &` for this repo's
Ollama path. A manually started Ollama process will not use the
`OLLAMA_HOST=0.0.0.0` systemd override, and the NemoClaw sandbox will not be
able to reach the inference server.

`OLLAMA_HOST=0.0.0.0` exposes Ollama on the host network. Use this on a trusted
local network, or apply host firewall rules appropriate for your environment.

## Quick Start

```bash
git clone https://github.com/nv-drollins/nemoclaw-vanilla.git
cd nemoclaw-vanilla
./install.sh
./scripts/show-openclaw-dashboard.sh --show-token
```

The dashboard helper prints the local OpenClaw dashboard URL. If your browser is on another machine, it also prints the SSH tunnel command to run from that machine.

The dashboard helper also prepares OpenClaw's Node runtime for the local NemoClaw inference route before it starts the dashboard forward.

## What The Installer Does

`./install.sh` runs `scripts/onboard-nemoclaw.sh`, which:

- uses the official NemoClaw installer from `https://www.nvidia.com/nemoclaw.sh`
- creates a vanilla sandbox named `vanilla-agent`
- uses `NEMOCLAW_PROVIDER=ollama` by default
- uses `NEMOCLAW_MODEL=qwen3.6:35b` by default
- generates NVIDIA CDI specs if they are missing
- ignores an active Python virtualenv during install
- bypasses the optional model-router pip install unless `NEMOCLAW_PROVIDER=routed`
- redirects accidental Ollama pulls to the requested model

`./scripts/show-openclaw-dashboard.sh` also:

- verifies Node can reach `https://inference.local/v1/models` through the OpenShell proxy
- installs the `inference.local` CA chain for Node
- restarts the in-sandbox OpenClaw gateway with the proxy-aware Node environment

## NemoClaw Onboarding Variables

`./install.sh` passes through the following variables to
`scripts/onboard-nemoclaw.sh` and the official NemoClaw installer.

| Variable | Default | Available options / examples | Purpose |
|---|---:|---|---|
| `NEMOCLAW_MODEL` | `qwen3.6:35b` when provider is `ollama` | Any model from `ollama list` for Ollama; provider model ID for other providers | Selects the model NemoClaw/OpenClaw should use. |
| `NEMOCLAW_PROVIDER` | `ollama` | `ollama`, `routed`; experimental `vllm` or `install-vllm` with `NEMOCLAW_EXPERIMENTAL=1`; other providers supported by the current NemoClaw installer | Selects the inference provider. |
| `NEMOCLAW_EXPERIMENTAL` | unset | `1` | Enables experimental provider choices such as local vLLM or managed local vLLM. |
| `NEMOCLAW_SANDBOX_NAME` | `vanilla-agent` | Any valid sandbox name, for example `my-agent` | Names the NemoClaw sandbox. Use a unique name to avoid replacing another sandbox. |
| `NEMOCLAW_POLICY_TIER` | `balanced` | `restricted`, `balanced`, `open` | Selects NemoClaw's baseline policy tier during onboarding. |
| `NEMOCLAW_INSTALL_REF` | unset (latest) | `v0.0.38`, `v0.0.43`, or another published installer ref | Pins the official NemoClaw installer for repeatable demo testing. Leave unset for latest. |
| `NEMOCLAW_INSTALL_FRESH` | `1` | `1` or `0` | Wrapper control. `1` passes `--fresh`; `0` omits it. |
| `NEMOCLAW_ROUTER_BYPASS` | `1` | `1` or `0` | Wrapper control. Skips the optional router pip install when provider is not `routed`. |
| `NEMOCLAW_STRICT_MODEL_PULL` | `1` | `1` or `0` | Wrapper control. Redirects unexpected Ollama pulls to `NEMOCLAW_MODEL`. |
| `NEMOCLAW_LOCAL_INFERENCE_TIMEOUT` | `300` | Seconds, for example `600` | Wait time for local inference validation and model warm-up. |
| `NEMOCLAW_SANDBOX_READY_TIMEOUT` | `600` | Seconds, for example `900` | Wait time for first-run sandbox image upload and startup. |
| `NEMOCLAW_OLLAMA_BIN` | auto-detected | Full path to `ollama` | Overrides which real Ollama binary the wrapper calls. |
| `NEMOCLAW_PIP_BIN` | auto-detected | Full path to `pip` or `pip3` | Overrides which real pip binary the router-bypass shim delegates to. |

| Script-set variable | Value | Notes |
|---|---:|---|
| `NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE` | `1` | Accepts the official installer's third-party software prompt for non-interactive setup. |
| `NEMOCLAW_NON_INTERACTIVE` | `1` | Keeps the installer in scripted mode. |
| `NEMOCLAW_YES` | `1` | Answers yes to supported installer confirmation prompts. |
| `NEMOCLAW_REAL_PIP_BIN` | auto-detected | Internal handoff from the pip wrapper to the real pip binary. |

## Onboarding Script Options

| Option | Source | Available options | Notes |
|---|---|---|---|
| `--sandbox NAME` | Repo wrapper | Any valid sandbox name | Same effect as `NEMOCLAW_SANDBOX_NAME=NAME`. |
| `--model MODEL` | Repo wrapper | Any provider-appropriate model ID | Same effect as `NEMOCLAW_MODEL=MODEL`. |
| `--provider PROVIDER` | Repo wrapper | `ollama`, `routed`, `vllm`, `install-vllm`, or another provider accepted by NemoClaw | Same effect as `NEMOCLAW_PROVIDER=PROVIDER`. |
| `--no-fresh` | Repo wrapper | Present or omitted | Omits the official installer `--fresh` flag. Useful when preserving an existing NemoClaw/OpenShell setup. |
| `--fresh` | Official NemoClaw installer | Passed by default through `NEMOCLAW_INSTALL_FRESH=1` | This repo does not require typing `--fresh`; the wrapper adds it unless disabled. |
| `--non-interactive` | Official NemoClaw installer | Always passed | Runs onboarding without prompts. |
| `--yes-i-accept-third-party-software` | Official NemoClaw installer | Always passed | Required by the official installer for non-interactive setup. |

## Examples

Use a different sandbox name:

```bash
NEMOCLAW_SANDBOX_NAME=my-agent ./install.sh
```

Use a different Ollama model:

```bash
NEMOCLAW_MODEL=qwen3.6:35b ./install.sh
```

Run without forcing a fresh NemoClaw installer pass:

```bash
./install.sh --no-fresh
```

Use vLLM instead of Ollama while keeping the router bypass:

```bash
NEMOCLAW_EXPERIMENTAL=1 \
NEMOCLAW_PROVIDER=vllm \
./install.sh
```

Use NemoClaw-managed vLLM instead:

```bash
NEMOCLAW_EXPERIMENTAL=1 \
NEMOCLAW_PROVIDER=install-vllm \
./install.sh
```

Do not use this router bypass with `NEMOCLAW_PROVIDER=routed`; in that mode, the router is the provider.

## Version Pinning And Diagnostics

Leave `NEMOCLAW_INSTALL_REF` unset for the current NemoClaw installer. To compare against a previous known demo lane, prefix the installer:

```bash
NEMOCLAW_INSTALL_REF=v0.0.38 ./install.sh
```

Check the installed stack before debugging a sandbox issue:

```bash
nemoclaw --version
openshell --version
nemoclaw vanilla-agent status
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

## Status

```bash
./scripts/status.sh
```

Or directly:

```bash
nemoclaw vanilla-agent status
```

## Dashboard

```bash
./scripts/show-openclaw-dashboard.sh --show-token
```

Without printing the token:

```bash
./scripts/show-openclaw-dashboard.sh
```

## Stop Or Remove

Stop the dashboard forward and stop the sandbox:

```bash
./scripts/stop-nemoclaw.sh
```

Destroy the sandbox:

```bash
./scripts/stop-nemoclaw.sh --destroy
```
