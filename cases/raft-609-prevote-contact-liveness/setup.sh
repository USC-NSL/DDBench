#!/usr/bin/env bash
# Setup script for raft-609-prevote-contact-liveness
# Clones the repository, checks out the buggy commit, and pre-downloads Go dependencies.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-609-prevote-contact-liveness"
BUGGY_COMMIT="42d34464b2d203e389e11ed6d43db698792c0604~1"
REPO_URL="https://github.com/hashicorp/raft.git"
export PATH="$PATH:/usr/local/go/bin"

echo "=== Setting up raft-609-prevote-contact-liveness ==="

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

# Clone raft
if [ ! -d "$WORK_DIR" ]; then
    echo "Cloning repository..."
    mkdir -p "$(dirname "$WORK_DIR")"
    git clone "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Checkout buggy commit
echo "Checking out buggy commit..."
git checkout $BUGGY_COMMIT 2>/dev/null || git checkout $(git rev-parse $BUGGY_COMMIT)

# Pre-download Go dependencies
echo "Downloading Go dependencies..."
go mod download

echo ""
echo "=== Setup complete ==="
echo "Workspace: $WORK_DIR"
