#!/usr/bin/env bash
# addon: claude-code
# description: Install Claude Code CLI for AI-assisted debugging
# runtime: Node.js (cached in persistent volume via tarball)
# requires: internet access (first run only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"

# Idempotent: verify claude exists AND its runtime (node) works
if [ -x "$TOOL_DIR/bin/claude" ] && [ -x "$TOOL_DIR/bin/node" ]; then
    echo "[addon:claude-code] already installed"
    exit 0
fi

echo "[addon:claude-code] installing ..."

ensure_node

# Install Claude Code into the persistent tool directory
npm_config_prefix="$TOOL_DIR" "$TOOL_DIR/bin/npm" install -g @anthropic-ai/claude-code >/dev/null 2>&1

echo "[addon:claude-code] installed to $TOOL_DIR/bin/claude"
