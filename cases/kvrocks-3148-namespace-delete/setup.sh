#!/usr/bin/env bash
# Setup script for kvrocks-3148-namespace-delete
# Clones the repository, checks out the buggy commit, and builds the project.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-3148-namespace-delete"
BUGGY_COMMIT="833ae36aa1d17e87be494724689b87e5234286ec~1"
REPO_URL="https://github.com/apache/kvrocks.git"

echo "=== Setting up kvrocks-3148-namespace-delete ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake git

# Check prerequisites
for cmd in git cmake g++; do
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
if [ ! -f "$WORK_DIR/build/kvrocks" ]; then
    echo "Building (this may take several minutes)..."
    mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Debug
    make -j$(nproc)
else
    echo "Binary already exists, skipping build."
fi

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/build/kvrocks"
