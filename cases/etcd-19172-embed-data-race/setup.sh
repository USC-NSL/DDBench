#!/usr/bin/env bash
# Setup script for etcd-19172-embed-data-race
# Clones the repository, checks out the buggy commit, and builds the project.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/etcd-19172-embed-data-race"
BUGGY_COMMIT="43431bd6f83b60d13a29ef9df53d7f04fe63fcfd~1"
REPO_URL="https://github.com/etcd-io/etcd.git"

export PATH="$PATH:/usr/local/go/bin"

echo "=== Setting up etcd-19172-embed-data-race ==="

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

# Checkout buggy commit
echo "Checking out buggy commit..."
git checkout $BUGGY_COMMIT 2>/dev/null || git checkout $(git rev-parse $BUGGY_COMMIT)

# Build
if [ ! -f "$WORK_DIR/bin/etcd" ]; then
    echo "Building (this may take several minutes)..."
    make build
else
    echo "Binary already exists, skipping build."
fi

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/bin/etcd"
