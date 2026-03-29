#!/usr/bin/env bash
# Setup script for bookkeeper-2614-recovery-fencing-gap
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
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/bookkeeper-2614-recovery-fencing-gap"
BUGGY_COMMIT="c11baba7dcedc227849021d0aee8303cfcc9765c"
REPO_URL="https://github.com/apache/bookkeeper.git"

echo "=== Setting up bookkeeper-2614-recovery-fencing-gap ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk maven git

# Check prerequisites
for cmd in git java mvn; do
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
echo "Checking out buggy commit ($BUGGY_COMMIT)..."
git checkout "$BUGGY_COMMIT"

# Build
echo "Building bookkeeper-server and dependencies (this may take 5-10 minutes)..."
mvn -pl bookkeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q

echo ""
echo "=== Setup complete ==="
echo "Project built at: $WORK_DIR"
