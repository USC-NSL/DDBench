#!/usr/bin/env bash
# addon: aider
# description: Install Aider AI coding assistant
# runtime: Python via uv (cached in persistent volume, no system python needed)
# requires: internet access (first run only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"

# Idempotent: verify aider exists AND its runtime (uv-managed python) works
if [ -x "$TOOL_DIR/bin/aider" ] && "$TOOL_DIR/bin/aider" --version &>/dev/null; then
    echo "[addon:aider] already installed"
    exit 0
fi

echo "[addon:aider] installing ..."

ensure_uv

# Install aider via uv tool (handles Python download + venv automatically).
# Everything goes into $TOOL_DIR/uv-python/, $TOOL_DIR/uv-tools/, $TOOL_DIR/bin/.
"$TOOL_DIR/bin/uv" tool install aider-chat 2>&1 | tail -1

echo "[addon:aider] installed to $TOOL_DIR/bin/aider"
