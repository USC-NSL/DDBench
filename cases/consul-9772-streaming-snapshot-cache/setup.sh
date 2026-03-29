#!/usr/bin/env bash
# Setup script for consul-9772-streaming-snapshot-cache
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
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/consul-9772-streaming-snapshot-cache"
BUGGY_COMMIT="363d738fd2ee1ee25ad872a63894cffa8faf9df2~1"
REPO_URL="https://github.com/hashicorp/consul.git"

echo "=== Setting up consul-9772-streaming-snapshot-cache ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential git

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

# Build (best-effort; the test can run without a full binary)
echo "Building (best-effort, test does not require the binary)..."
go build -o bin/consul ./... 2>/dev/null || echo "Binary build skipped (not required for this case)."

echo ""
echo "=== Setup complete ==="
