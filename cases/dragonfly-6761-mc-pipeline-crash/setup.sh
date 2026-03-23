#!/usr/bin/env bash
# Setup script for dragonfly-6761-mc-pipeline-crash
# Clones the repository, checks out the buggy commit, and builds the project.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6761-mc-pipeline-crash"
BUGGY_COMMIT="5a78b758ff21f179963de4da9e7ad301459e23bb~1"
REPO_URL="https://github.com/dragonflydb/dragonfly.git"

echo "=== Setting up dragonfly-6761-mc-pipeline-crash ==="

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
