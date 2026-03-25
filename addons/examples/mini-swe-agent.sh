#!/usr/bin/env bash
# addon: mini-swe-agent
# description: Install mini-swe-agent (minimalist SWE-bench agent)
# runtime: Python via uv (cached in persistent volume, no system python needed)
# requires: internet access (first run only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"

# Idempotent: verify mini exists AND its runtime (uv-managed python) works
if [ -x "$TOOL_DIR/bin/mini" ] && "$TOOL_DIR/bin/mini" --help &>/dev/null; then
    echo "[addon:mini-swe-agent] already installed"
    exit 0
fi

echo "[addon:mini-swe-agent] installing ..."

ensure_uv

# Install mini-swe-agent via uv tool (handles Python >=3.10 download + venv automatically).
# Everything goes into $TOOL_DIR/uv-python/, $TOOL_DIR/uv-tools/, $TOOL_DIR/bin/.
"$TOOL_DIR/bin/uv" tool install mini-swe-agent 2>&1 | tail -1

echo "[addon:mini-swe-agent] installed to $TOOL_DIR/bin/mini"
