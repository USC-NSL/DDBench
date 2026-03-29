#!/usr/bin/env bash
# Setup script for consul-8377-snapshot-restore-index
# Clones the repository, checks out the buggy commit, and builds the project.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/consul-8377-snapshot-restore-index"
BUGGY_COMMIT="9bc9d3014d2d8f48c4c87926bfb98c8536364532~1"
REPO_URL="https://github.com/hashicorp/consul.git"

echo "=== Setting up consul-8377-snapshot-restore-index ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential git curl jq

# Check prerequisites
for cmd in git go curl jq; do
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

# Build
if [ ! -f "$WORK_DIR/bin/consul" ]; then
    echo "Building (this may take several minutes)..."
    make dev-build
else
    echo "Binary already exists, skipping build."
fi

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/bin/consul"
