#!/usr/bin/env bash
# addon: rr-debugger
# description: Install Mozilla rr (record & replay debugger)
# runtime: Extracted from .deb into persistent volume (no apt-get install on repeat runs)
# requires: internet access (first run only), SYS_PTRACE capability (already added by bench.sh)
set -euo pipefail

TOOL_DIR="${ADDON_TOOL_DIR:-/opt/tools}"
export PATH="$TOOL_DIR/bin:$PATH"

# Idempotent: skip if rr binary exists in persistent cache
if [ -x "$TOOL_DIR/bin/rr" ]; then
    echo "[addon:rr-debugger] already installed (cached)"
else
    echo "[addon:rr-debugger] installing ..."

    # Download the .deb package without installing it, then extract to persistent volume.
    # This avoids apt-get install (ephemeral) and caches the full package layout.
    apt-get update -qq >/dev/null 2>&1
    local_deb="/tmp/rr_download.deb"
    apt-get download -o Dir::Cache::archives=/tmp rr >/dev/null 2>&1 \
        && mv /tmp/rr_*.deb "$local_deb" 2>/dev/null \
        || apt-get download rr -o APT::Get::Download-Only=true 2>/dev/null

    # Find the downloaded .deb
    if [ ! -f "$local_deb" ]; then
        local_deb=$(ls /tmp/rr_*.deb 2>/dev/null | head -1)
    fi
    if [ -z "$local_deb" ] || [ ! -f "$local_deb" ]; then
        # Fallback: just apt-get install (ephemeral but works)
        echo "[addon:rr-debugger] WARNING: .deb download failed, falling back to apt-get install"
        apt-get install -y -qq rr >/dev/null 2>&1
    else
        # Extract full package (binary + preload libraries) into persistent volume
        mkdir -p "$TOOL_DIR/rr-pkg"
        dpkg-deb -x "$local_deb" "$TOOL_DIR/rr-pkg"
        rm -f "$local_deb"

        # Symlink the binary into $TOOL_DIR/bin/
        mkdir -p "$TOOL_DIR/bin"
        ln -sf "$TOOL_DIR/rr-pkg/usr/bin/rr" "$TOOL_DIR/bin/rr"

        # rr needs its preload libraries at runtime. Set the search path via symlink
        # so rr can find librr_preload.so relative to its expected location.
        if [ -d "$TOOL_DIR/rr-pkg/usr/lib/rr" ]; then
            mkdir -p "$TOOL_DIR/lib"
            ln -sfn "$TOOL_DIR/rr-pkg/usr/lib/rr" "$TOOL_DIR/lib/rr"
        fi
    fi

    echo "[addon:rr-debugger] installed to $TOOL_DIR/bin/rr"
fi

# rr requires perf_event_paranoid <= 1
if [ -f /proc/sys/kernel/perf_event_paranoid ]; then
    current=$(cat /proc/sys/kernel/perf_event_paranoid)
    if [ "$current" -gt 1 ] 2>/dev/null; then
        echo "[addon:rr-debugger] WARNING: perf_event_paranoid=$current (needs <=1)"
        echo "  Run on host: sudo sysctl kernel.perf_event_paranoid=1"
        echo "  Or add --privileged to Docker run args"
    fi
fi
