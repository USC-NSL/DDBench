#!/usr/bin/env bash
# addon: claude-code
# description: Install Claude Code CLI for AI-assisted debugging
# runtime: Node.js (cached in persistent volume via tarball)
# requires: internet access (first run only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"

CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.299}"
PKG_JSON="$TOOL_DIR/lib/node_modules/@anthropic-ai/claude-code/package.json"

# Idempotent: verify claude exists at the pinned version AND its runtime (node) works
if [ -x "$TOOL_DIR/bin/claude" ] && [ -x "$TOOL_DIR/bin/node" ] \
   && grep -q "\"version\": *\"${CLAUDE_CODE_VERSION}\"" "$PKG_JSON" 2>/dev/null; then
    echo "[addon:claude-code] already installed (v${CLAUDE_CODE_VERSION})"
    exit 0
fi

echo "[addon:claude-code] installing v${CLAUDE_CODE_VERSION} ..."

ensure_node

# Install Claude Code into the persistent tool directory
npm_config_prefix="$TOOL_DIR" "$TOOL_DIR/bin/npm" install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" >/dev/null 2>&1

echo "[addon:claude-code] installed to $TOOL_DIR/bin/claude"
