#!/usr/bin/env bash
# addon: mini-swe-agent
# description: Install mini-swe-agent (minimalist SWE-bench agent, pinned to v2.2.8)
# runtime: Python via uv (cached in persistent volume, no system python needed)
# requires: internet access (first run only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"

MSWEA_VERSION="${MSWEA_VERSION:-2.2.8}"

# Idempotent: verify mini exists AND its runtime (uv-managed python) works
if [ -x "$TOOL_DIR/bin/mini" ] && "$TOOL_DIR/bin/mini" --help &>/dev/null; then
    INSTALLED_VER=$("$TOOL_DIR/bin/mini" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    if [ "$INSTALLED_VER" = "$MSWEA_VERSION" ] || [ "$INSTALLED_VER" = "unknown" ]; then
        echo "[addon:mini-swe-agent] already installed (v${INSTALLED_VER})"
        exit 0
    fi
    echo "[addon:mini-swe-agent] v${INSTALLED_VER} installed, v${MSWEA_VERSION} pinned: reinstalling"
fi

echo "[addon:mini-swe-agent] installing v${MSWEA_VERSION} ..."

ensure_uv

# Install mini-swe-agent via uv tool (handles Python >=3.10 download + venv automatically).
# Everything goes into $TOOL_DIR/uv-python/, $TOOL_DIR/uv-tools/, $TOOL_DIR/bin/.
# Version is pinned for reproducibility across benchmark runs.
"$TOOL_DIR/bin/uv" tool install --force "mini-swe-agent==${MSWEA_VERSION}" 2>&1 | tail -1

# Post-install verification
if "$TOOL_DIR/bin/mini" --help &>/dev/null; then
    echo "[addon:mini-swe-agent] installed v${MSWEA_VERSION} to $TOOL_DIR/bin/mini"
else
    echo "[addon:mini-swe-agent] ERROR: installation succeeded but 'mini --help' failed" >&2
    exit 1
fi
