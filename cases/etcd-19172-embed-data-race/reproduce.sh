#!/usr/bin/env bash
# Reproduction and verification script for etcd-19172-embed-data-race
# Runs the embed integration test with the race detector and reports PASS/FAIL.
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/etcd-19172-embed-data-race"

export PATH="$PATH:/usr/local/go/bin"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

# Clean up any leftover etcd processes
pkill -f "etcd --name" 2>/dev/null || true
sleep 1

echo "=== Reproducing etcd-19172-embed-data-race ==="

cleanup() {
    pkill -f "etcd --name" 2>/dev/null || true
}
trap cleanup EXIT

echo "Running TestEmbedEtcd with -race up to 10 times..."

cd "$WORK_DIR/tests/integration/embed"

RACE_DETECTED=0
for i in $(seq 1 10); do
    echo "=== Run $i/10 ==="
    OUTPUT=$(go test -race -run "^TestEmbedEtcd" -count=1 -timeout 120s 2>&1)
    if echo "$OUTPUT" | grep -q "DATA RACE"; then
        echo "$OUTPUT" | grep -A 20 "DATA RACE" | head -30
        RACE_DETECTED=1
        break
    fi
    echo "No race detected on run $i"
done

echo ""
if [ "$RACE_DETECTED" -eq 1 ]; then
    echo "FAIL: Bug is present — data race detected between Etcd.Close() and Etcd.errHandler()"
    exit 1
else
    echo "PASS: Bug is fixed — no data race detected in 10 runs"
    exit 0
fi
