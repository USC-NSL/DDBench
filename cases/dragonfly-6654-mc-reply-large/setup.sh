#!/usr/bin/env bash
# Setup script for dragonfly-6654-mc-reply-large
# Clones the repository, checks out the buggy commit, and builds the project.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6654-mc-reply-large"
BUGGY_COMMIT="ff4ef508985cb91a7fdf418682af1534c24acf83~1"
REPO_URL="https://github.com/dragonflydb/dragonfly.git"

echo "=== Setting up dragonfly-6654-mc-reply-large ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake ninja-build git

# Check prerequisites
for cmd in git cmake ninja g++; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Clone
if [ ! -d "$WORK_DIR" ]; then
    echo "Cloning repository..."
    git clone --recurse-submodules "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Checkout buggy commit
echo "Checking out buggy commit..."
git checkout $BUGGY_COMMIT 2>/dev/null || git checkout $(git rev-parse $BUGGY_COMMIT)
git submodule update --init --recursive

# Build
if [ ! -f "$WORK_DIR/build-dbg/dragonfly" ]; then
    echo "Building (this may take several minutes)..."
    ./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug -DWITH_AWS=OFF
    cd build-dbg && ninja dragonfly
else
    echo "Binary already exists, skipping build."
fi

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/build-dbg/dragonfly"
