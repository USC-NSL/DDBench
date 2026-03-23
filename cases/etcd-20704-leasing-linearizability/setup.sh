#!/usr/bin/env bash
# Setup script for etcd-20704-leasing-linearizability
# Clones the repository, checks out the buggy commit, and builds the project.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/etcd-20704-leasing-linearizability"
REPO_URL="https://github.com/etcd-io/etcd.git"

export PATH="$PATH:/usr/local/go/bin"

echo "=== Setting up etcd-20704-leasing-linearizability ==="

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

# Checkout main branch (bug exists on main)
echo "Checking out main branch..."
git checkout main
git pull origin main

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
