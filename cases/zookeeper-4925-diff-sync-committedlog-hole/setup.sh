#!/usr/bin/env bash
# Setup script for zookeeper-4925-diff-sync-committedlog-hole
# Clones the repository, checks out the buggy commit, and builds the project.
# -- Docker mode (preferred) --
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"
fi
# -- Host fallback (no Docker) --
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/zookeeper-4925-diff-sync-committedlog-hole"
BUGGY_COMMIT="e5dd60bf0512ccc1e090d99410a8da48623219da~1"
REPO_URL="https://github.com/apache/zookeeper.git"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

echo "=== Setting up zookeeper-4925-diff-sync-committedlog-hole ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git openjdk-11-jdk maven

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
echo "Checking out buggy commit..."
git checkout $BUGGY_COMMIT 2>/dev/null || git checkout $(git rev-parse $BUGGY_COMMIT)

# Build
if [ ! -f "$WORK_DIR/zookeeper-server/target/classes/org/apache/zookeeper/server/ZooKeeperServer.class" ]; then
    echo "Building (this may take several minutes)..."
    mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
else
    echo "Build artifacts already exist, skipping build."
fi

echo ""
echo "=== Setup complete ==="
echo "Project: $WORK_DIR"
