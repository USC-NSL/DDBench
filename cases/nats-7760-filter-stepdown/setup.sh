#!/usr/bin/env bash
# Setup script for nats-7760-filter-stepdown
# Clones the repository, checks out the buggy version, builds the server, and installs nats CLI.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7760-filter-stepdown"
BUGGY_TAG="v2.12.3"
REPO_URL="https://github.com/nats-io/nats-server.git"

export PATH=$PATH:/usr/local/go/bin

echo "=== Setting up nats-7760-filter-stepdown ==="

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

# Install nats CLI
echo "Installing nats CLI..."
GOBIN="$WORK_DIR" go install github.com/nats-io/natscli/nats@latest 2>/dev/null || {
    echo "WARNING: Could not install nats CLI. Please install it manually."
}

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/nats-server"
if [ -f "$WORK_DIR/nats" ]; then
    echo "CLI: $WORK_DIR/nats"
fi
