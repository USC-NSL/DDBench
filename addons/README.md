# Addons

Addons inject tools — AI coding agents, debuggers, profilers — into bug-bench containers at runtime, without modifying base Docker images.

## Quick Start

```bash
# Drop into a shell with Claude Code pre-installed
./bench.sh shell dragonfly-6856-flushslots-oob --addon claude-code

# Launch an agent directly
./bench.sh agent dragonfly-6856-flushslots-oob --addon claude-code

# Stack multiple addons
./bench.sh shell dragonfly-6856-flushslots-oob --addon claude-code --addon custom-gdb-dashboard
```

First run downloads and installs the tool (~1-3 min depending on addon). Subsequent runs are instant thanks to a persistent Docker volume cache (`bug-bench-tools`).

## Available Examples

| Addon | Tool | Description |
|-------|------|-------------|
| `claude-code` | [Claude Code](https://claude.ai/code) | Anthropic's CLI coding agent |
| `aider` | [Aider](https://aider.chat) | AI pair programming in the terminal |
| `codex` | [Codex CLI](https://github.com/openai/codex) | OpenAI's coding agent |
| `mini-swe-agent` | [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent) | Minimalist SWE-bench agent (~100 lines, bash-only tool) |
| `custom-gdb-dashboard` | [GDB Dashboard](https://github.com/cyrus-and/gdb-dashboard) | Rich terminal UI for GDB |
| `rr-debugger` | [rr](https://rr-project.org) | Record & replay debugger |

## Runtime Caching Strategy

Addons must install **everything** — including language runtimes — into the persistent volume at `/opt/tools/`. Using `apt-get` for runtimes (e.g., `apt-get install nodejs`) would put them in the ephemeral container filesystem, requiring reinstallation on every container start.

| Runtime | Strategy | Persistent? |
|---------|----------|-------------|
| **Node.js** | Official tarball extracted to `/opt/tools/` | Yes — fully cached |
| **Python** | [uv](https://docs.astral.sh/uv/) manages Python + venvs in `/opt/tools/` | Yes — fully cached |
| **System binaries** (rr) | `.deb` downloaded + extracted to `/opt/tools/rr-pkg/` | Yes — fully cached |
| **Config files** (.gdbinit) | Cached in `/opt/tools/share/`, copied to `$HOME/` each start | Partial — download cached, copy instant |

The shared helper `_runtime.sh` provides `ensure_node` and `ensure_uv` for common runtimes.

## Writing Your Own Addon

Create a `.sh` file in `addons/` (user scripts) or `addons/examples/` (shipped with repo).

### Contract

Every addon script must:

1. **Be idempotent** — check that the tool AND its runtime are functional, exit early if so
2. **Be non-interactive** — no prompts, no user input
3. **Print status** — `[addon:<name>] installing ...` / `[addon:<name>] already installed`
4. **Install into `ADDON_TOOL_DIR`** — use `${ADDON_TOOL_DIR:-/opt/tools}` for persistent caching
5. **Never use apt-get for runtimes** — use tarballs/managed installs into the persistent volume instead
6. **Work on Ubuntu 24.04** — both base-cpp and base-go images use this base

### Template (Node.js tool)

```bash
#!/usr/bin/env bash
# addon: my-node-tool
# description: One-line description
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"

# Idempotent: check tool AND runtime
if [ -x "$TOOL_DIR/bin/my-tool" ] && [ -x "$TOOL_DIR/bin/node" ]; then
    echo "[addon:my-tool] already installed"
    exit 0
fi

echo "[addon:my-tool] installing ..."
ensure_node
npm_config_prefix="$TOOL_DIR" "$TOOL_DIR/bin/npm" install -g my-tool-package >/dev/null 2>&1
echo "[addon:my-tool] installed"
```

### Template (Python tool)

```bash
#!/usr/bin/env bash
# addon: my-python-tool
# description: One-line description
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"

# Idempotent: check tool works end-to-end
if command -v my-tool &>/dev/null && my-tool --version &>/dev/null; then
    echo "[addon:my-tool] already installed"
    exit 0
fi

echo "[addon:my-tool] installing ..."
ensure_uv
"$TOOL_DIR/bin/uv" tool install my-tool-package 2>&1 | tail -1
echo "[addon:my-tool] installed"
```

### The `_runtime.sh` Helper

Source `_runtime.sh` from your addon to get access to:

| Function | What it does |
|----------|-------------|
| `ensure_node` | Downloads Node.js tarball to `$TOOL_DIR/` (provides `node`, `npm`, `npx`) |
| `ensure_uv` | Downloads [uv](https://docs.astral.sh/uv/) static binary (can install Python + manage packages without system Python) |

Both are idempotent — instant no-op if already installed.

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"
```

### Resolution Order

When you pass `--addon my-tool`, bench.sh looks for:

1. `addons/my-tool.sh` — your custom script (gitignored, takes priority)
2. `addons/examples/my-tool.sh` — shipped example

This lets you override any example with your own version.

## API Key Management

Agent addons need API keys. These are passed from your host environment automatically:

| Variable | Agent |
|----------|-------|
| `ANTHROPIC_API_KEY` | Claude Code, mini-swe-agent |
| `OPENAI_API_KEY` | Aider, Codex, mini-swe-agent |
| `GEMINI_API_KEY` | Aider (Gemini backend) |
| `MSWEA_MODEL_NAME` | mini-swe-agent (optional, sets default model) |

Set them on your host (e.g., in `~/.bashrc`), and `bench.sh` forwards them into the container.

Agent config directories (e.g., `~/.claude/`) are also mounted read-only if they exist.

## Persistent Tool Cache

Addon installations are cached in a Docker volume (`bug-bench-tools`) mounted at `/opt/tools`. This volume is shared across all 31 cases and all container types (C++, Go).

**What's cached (install once, use everywhere):**
- Language runtimes: Node.js binary, uv-managed Python
- Tool binaries: `claude`, `aider`, `codex`, and their dependencies
- Downloaded assets: `.gdbinit` for gdb-dashboard

**What's NOT cached (per-container, fast):**
- `$HOME/` config files — copied from cache each start (~instant)
- Optional extras like `pygments` for gdb-dashboard (best-effort pip install)

**Cache management:**
- `./bench.sh clean-all` also removes the cache
- To reset just the cache: `docker volume rm bug-bench-tools`

## FAQ

**Can I use addons with `bench.sh reproduce`?**
No. `reproduce` is a hermetic test — no extra tools. Use `shell` or `agent` instead.

**Do addons modify the Docker image?**
No. Addons install at container runtime. The base images remain tool-agnostic.

**Can I use addons with VS Code devcontainers?**
Not automatically (yet). For now, open a terminal inside the devcontainer and run the addon script manually: `bash /addons/examples/claude-code.sh`.
