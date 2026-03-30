#!/usr/bin/env bash
# Setup script for kafka-15170-endless-rebalance-loop
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
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kafka-15170-endless-rebalance-loop"
BUGGY_COMMIT="f0291ac74b88b988c4ab07c16286942838ba4556~1"
REPO_URL="https://github.com/apache/kafka.git"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

echo "=== Setting up kafka-15170-endless-rebalance-loop ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git openjdk-17-jdk

# Check prerequisites
for cmd in git java; do
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
if [ ! -f "$WORK_DIR/clients/build/classes/java/main/org/apache/kafka/clients/consumer/KafkaConsumer.class" ]; then
    echo "Building (this may take several minutes)..."
    ./gradlew :clients:compileJava :clients:compileTestJava -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet
else
    echo "Build artifacts already exist, skipping build."
fi

echo ""
echo "=== Setup complete ==="
echo "Project: $WORK_DIR"
