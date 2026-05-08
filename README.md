# Vanilla NemoClaw with Local Ollama

This repo installs a plain NemoClaw/OpenClaw sandbox that uses local Ollama inference by default.

It also includes the small router bypass we needed on DGX Spark: when the selected provider is not `routed`, the installer skips the optional `llm-router` pip install that can fail in externally managed Python environments or active virtualenvs.

Default model:

```bash
qwen3.6:35b
```

## Before You Begin

Run this on the Linux host where NemoClaw should run. The host should already have:

- Docker
- NVIDIA Container Toolkit
- NVIDIA drivers and `nvidia-ctk`
- `curl`
- `sudo` access
- enough GPU memory for the selected Ollama model

Ollama may already be installed, or NemoClaw can install/start it during onboarding.

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

## Options

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
