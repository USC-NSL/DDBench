#!/usr/bin/env bash
# addon: codex
# description: Install OpenAI Codex CLI
# runtime: Node.js (cached in persistent volume via tarball)
# requires: internet access (first run only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_runtime.sh"

CODEX_VERSION="${CODEX_VERSION:-0.162.1}"
PKG_JSON="$TOOL_DIR/lib/node_modules/@openai/codex/package.json"

# Idempotent: verify codex exists at the pinned version AND its runtime (node) works
if [ -x "$TOOL_DIR/bin/codex" ] && [ -x "$TOOL_DIR/bin/node" ] \
   && grep -q "\"version\": *\"${CODEX_VERSION}\"" "$PKG_JSON" 2>/dev/null; then
    echo "[addon:codex] already installed (v${CODEX_VERSION})"
    exit 0
fi

echo "[addon:codex] installing v${CODEX_VERSION} ..."

ensure_node

# Install Codex CLI into the persistent tool directory
npm_config_prefix="$TOOL_DIR" "$TOOL_DIR/bin/npm" install -g "@openai/codex@${CODEX_VERSION}" >/dev/null 2>&1

echo "[addon:codex] installed to $TOOL_DIR/bin/codex"
