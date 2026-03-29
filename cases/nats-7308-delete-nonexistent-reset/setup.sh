#!/usr/bin/env bash
# Setup script for nats-7308-delete-nonexistent-reset
# Clones the repository, checks out the buggy version, and builds the project.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7308-delete-nonexistent-reset"
BUGGY_TAG="v2.11.8"
REPO_URL="https://github.com/nats-io/nats-server.git"

export PATH=$PATH:/usr/local/go/bin

echo "=== Setting up nats-7308-delete-nonexistent-reset ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git golang-go

# Check prerequisites
for cmd in git go; do
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

# Checkout buggy version
echo "Checking out $BUGGY_TAG..."
git checkout "$BUGGY_TAG"

# Build
echo "Building nats-server..."
go build -o nats-server .

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/nats-server"
