#!/usr/bin/env bash
# Setup script for raft-rs-221-campaign-conf-change
# Clones the repository, checks out the buggy commit, and builds the test harness.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-rs-221-campaign-conf-change"
BUGGY_COMMIT="aa131db1ba95166501c1cf5b8d90cd7c7bde2308"
REPO_URL="https://github.com/tikv/raft-rs.git"
export PATH="$HOME/.cargo/bin:$PATH"

echo "=== Setting up raft-rs-221-campaign-conf-change ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential git curl pkg-config libssl-dev cmake protobuf-compiler

# Install Rust if not present
if ! command -v cargo &>/dev/null; then
    echo "Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# Check prerequisites
for cmd in git cargo rustc; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Clone
if [ ! -d "$WORK_DIR" ]; then
    echo "Cloning repository..."
    git clone "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Checkout buggy commit
echo "Checking out buggy commit..."
git checkout $BUGGY_COMMIT 2>/dev/null || git checkout $(git rev-parse $BUGGY_COMMIT)

# Build test harness (compile tests without running)
echo "Building test harness (this may take a few minutes on first run)..."
RUSTFLAGS='--cap-lints allow' cargo test --no-run 2>&1 | tail -5

echo ""
echo "=== Setup complete ==="
echo "Workspace: $WORK_DIR"
