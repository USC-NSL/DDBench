#!/usr/bin/env bash
# Reproduction and verification script for nats-7707-wq-consumer-map-crash
# Injects a Go test that triggers the concurrent map access race,
# runs it with the Go race detector, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7707-wq-consumer-map-crash"
TEST_FILE="$WORK_DIR/server/race_wq_partition_test.go"
OUTPUT_FILE=$(mktemp)

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -f "$WORK_DIR/nats-server" ]; then
    echo "ERROR: Binary not found at $WORK_DIR/nats-server. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing nats-7707-wq-consumer-map-crash ==="

cleanup() {
    rm -f "$TEST_FILE" "$OUTPUT_FILE"
}
trap cleanup EXIT

# Inject the test into the server package
cp /bench/inject_test.go "$TEST_FILE" 2>/dev/null || cp "$CASE_DIR/inject_test.go" "$TEST_FILE"

# The race is reliably detected by Go's -race detector with 256 pre-seeded
# consumers (widens the partitionUnique iteration window). Without -race,
# the Go runtime's concurrent-map-access check is probabilistic and unreliable.
# Run -race 3 times — with 256 seeded consumers the race typically fires on
# the first attempt.
echo "Running TestWQConsumerPartitionRace with -race detector (up to 3 iterations)..."

RACE_DETECTED=0

for i in $(seq 1 3); do
    echo "=== Run $i/3 (with -race) ==="
    go test -race -run "^TestWQConsumerPartitionRace$" -count=1 -timeout 120s ./server/ > "$OUTPUT_FILE" 2>&1 || true

    # Use grep on a file (not pipe from echo) to avoid broken-pipe issues
    # with pipefail when the output is large (race detector produces ~700KB).
    if grep -q "concurrent map" "$OUTPUT_FILE"; then
        grep -B 2 -A 10 "concurrent map" "$OUTPUT_FILE" | head -30
        RACE_DETECTED=1
        break
    fi

    if grep -q "DATA RACE" "$OUTPUT_FILE"; then
        grep -A 20 "DATA RACE" "$OUTPUT_FILE" | head -30
        RACE_DETECTED=1
        break
    fi

    echo "No race detected on run $i"
done

echo ""
if [ "$RACE_DETECTED" -eq 1 ]; then
    echo "FAIL: Bug is present — data race detected in consumer partition map access"
    exit 1
else
    echo "PASS: Bug is fixed — no race or crash detected in 3 runs"
    exit 0
fi
