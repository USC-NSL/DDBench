#!/usr/bin/env bash
# addon: custom-gdb-dashboard
# description: Install GDB Dashboard for a rich terminal-based GDB UI
# runtime: gdb (pre-installed in base-cpp containers)
# requires: internet access (first run only for download, instant thereafter)
# note: .gdbinit lives in $HOME (ephemeral), but the downloaded file is cached
#       in the persistent volume. Each container start copies from cache (~instant).
set -euo pipefail

TOOL_DIR="${ADDON_TOOL_DIR:-/opt/tools}"
CACHE_DIR="$TOOL_DIR/share/gdb-dashboard"
TARGET="$HOME/.gdbinit"

if ! command -v gdb &>/dev/null; then
    echo "[addon:custom-gdb-dashboard] WARNING: gdb not found — skipping (only useful in C++ containers)"
    exit 0
fi

# Download to persistent cache if not already there
if [ ! -f "$CACHE_DIR/.gdbinit" ]; then
    echo "[addon:custom-gdb-dashboard] downloading ..."
    mkdir -p "$CACHE_DIR"
    curl -fsSL -o "$CACHE_DIR/.gdbinit" \
        https://raw.githubusercontent.com/cyrus-and/gdb-dashboard/master/.gdbinit
fi

# Copy from cache to $HOME (fast, needed each container since $HOME is ephemeral)
if [ ! -f "$TARGET" ]; then
    cp "$CACHE_DIR/.gdbinit" "$TARGET"
fi

# Install pygments for syntax highlighting (optional, best-effort)
if command -v pip3 &>/dev/null; then
    pip3 install --quiet pygments 2>/dev/null || true
elif command -v python3 &>/dev/null; then
    python3 -m pip install --quiet pygments 2>/dev/null || true
fi

echo "[addon:custom-gdb-dashboard] ready (sourced via ~/.gdbinit)"
