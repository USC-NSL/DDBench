#!/usr/bin/env bash
# addon: codex
# description: Install OpenAI Codex CLI
# runtime: Node.js (cached in persistent volume via tarball)
# requires: internet access (first run only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"

# Idempotent: verify codex exists AND its runtime (node) works
if [ -x "$TOOL_DIR/bin/codex" ] && [ -x "$TOOL_DIR/bin/node" ]; then
    echo "[addon:codex] already installed"
    exit 0
fi

echo "[addon:codex] installing ..."

ensure_node

# Install Codex CLI into the persistent tool directory
npm_config_prefix="$TOOL_DIR" "$TOOL_DIR/bin/npm" install -g @openai/codex >/dev/null 2>&1

echo "[addon:codex] installed to $TOOL_DIR/bin/codex"
