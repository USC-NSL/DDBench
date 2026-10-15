#!/usr/bin/env bash
# _runtime.sh — Persistent runtime bootstrapping for addon scripts.
# Source this file; do not execute directly.
#
# Provides:
#   ensure_node    — Install Node.js from official tarball into TOOL_DIR
#   ensure_uv      — Install uv (Python package manager) into TOOL_DIR
#
# All runtimes are installed into the persistent tool volume so they survive
# across container restarts and are shared across all cases.
#
# Versions are pinned for reproducibility. Override them by setting the
# variables below in a custom addon (addons/<name>.sh) before sourcing this file.

TOOL_DIR="${ADDON_TOOL_DIR:-/opt/tools}"
mkdir -p "$TOOL_DIR/bin"
export PATH="$TOOL_DIR/bin:$PATH"

# uv environment — all Python tooling goes into the persistent volume
export UV_PYTHON_INSTALL_DIR="$TOOL_DIR/uv-python"
export UV_TOOL_DIR="$TOOL_DIR/uv-tools"
export UV_TOOL_BIN_DIR="$TOOL_DIR/bin"

NODE_VERSION="${NODE_VERSION:-22.12.0}"
UV_VERSION="${UV_VERSION:-0.11.3}"

# Install Node.js from official tarball (not apt-get) into TOOL_DIR.
# Provides: node, npm, npx — all persistent.
ensure_node() {
    if [ -x "$TOOL_DIR/bin/node" ]; then
        return 0
    fi
    echo "[runtime] installing Node.js $NODE_VERSION ..."
    local arch
    case "$(uname -m)" in
        x86_64)  arch="x64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="armv7l" ;;
        *)       echo "[runtime] ERROR: unsupported architecture $(uname -m)"; return 1 ;;
    esac
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${arch}.tar.gz" \
        | tar -xz -C "$TOOL_DIR" --strip-components=1 --no-same-owner
    echo "[runtime] Node.js $("$TOOL_DIR/bin/node" --version) ready at $TOOL_DIR/bin/node"
}

# Install uv (Astral's Python package manager) as a single static binary.
# Provides: uv, uvx — can install Python, create venvs, manage tools.
ensure_uv() {
    if [ -x "$TOOL_DIR/bin/uv" ] && "$TOOL_DIR/bin/uv" --version 2>/dev/null | grep -q "^uv ${UV_VERSION}\b"; then
        return 0
    fi
    echo "[runtime] installing uv $UV_VERSION ..."
    # Versioned installer (installs exactly $UV_VERSION).
    curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" \
        | env UV_INSTALL_DIR="$TOOL_DIR/bin" UV_NO_MODIFY_PATH=1 sh >/dev/null 2>&1
    echo "[runtime] uv ready at $TOOL_DIR/bin/uv"
}
