#!/usr/bin/env bash
# addon: aider
# description: Install Aider AI coding assistant
# runtime: Python via uv (cached in persistent volume, no system python needed)
# requires: internet access (first run only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"

AIDER_VERSION="${AIDER_VERSION:-0.86.2}"

# Idempotent: verify aider exists at the pinned version AND its runtime (uv-managed python) works
if [ -x "$TOOL_DIR/bin/aider" ] && "$TOOL_DIR/bin/aider" --version 2>/dev/null | grep -q "\b${AIDER_VERSION}\b"; then
    echo "[addon:aider] already installed (v${AIDER_VERSION})"
    exit 0
fi

echo "[addon:aider] installing v${AIDER_VERSION} ..."

ensure_uv

# Install aider via uv tool (handles Python download + venv automatically).
# Everything goes into $TOOL_DIR/uv-python/, $TOOL_DIR/uv-tools/, $TOOL_DIR/bin/.
"$TOOL_DIR/bin/uv" tool install --force "aider-chat==${AIDER_VERSION}" 2>&1 | tail -1

echo "[addon:aider] installed to $TOOL_DIR/bin/aider"
