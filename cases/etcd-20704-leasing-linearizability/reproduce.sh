#!/usr/bin/env bash
# Reproduction and verification script for etcd-20704-leasing-linearizability
# Starts a single-node etcd, runs a Go test for the Delete+Put leasing cache race,
# and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/etcd-20704-leasing-linearizability"
BINARY="$WORK_DIR/bin/etcd"
DATA_DIR="$WORK_DIR/etcd-20704-data"
PORT=2379
TEST_FILE="$WORK_DIR/leasing_bug.go"

export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

# Cleanup from previous runs
pkill -f "etcd.*etcd-20704" 2>/dev/null || true
sleep 1
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"

echo "=== Reproducing etcd-20704-leasing-linearizability ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
    rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Start etcd
echo "Starting single-node etcd..."
"$BINARY" --data-dir "$DATA_DIR" &>/dev/null &
SERVER_PID=$!
sleep 3

# Check server started
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: etcd failed to start."
    exit 1
fi

# Write the Go test program
cat > "$TEST_FILE" << 'GOEOF'
package main

import (
	"context"
	"fmt"
	"os"
	"sync"
	"time"

	clientv3 "go.etcd.io/etcd/client/v3"
	"go.etcd.io/etcd/client/v3/leasing"
)

func main() {
	cli, err := clientv3.New(clientv3.Config{
		Endpoints:   []string{"http://127.0.0.1:2379"},
		DialTimeout: 5 * time.Second,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to connect: %v\n", err)
		os.Exit(2)
	}
	defer cli.Close()

	lkv, closeFn, err := leasing.NewKV(cli, "leasing-test/")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create leasing KV: %v\n", err)
		os.Exit(2)
	}
	if closeFn != nil {
		defer closeFn()
	}

	ctx := context.Background()
	key := "/test/leasing-key"
	bugFound := false

	for iter := 0; iter < 1000; iter++ {
		// Setup: put a value
		lkv.Put(ctx, key, "initial")

		var wg sync.WaitGroup
		wg.Add(2)

		// Goroutine 1: Delete the key
		go func() {
			defer wg.Done()
			lkv.Delete(ctx, key)
		}()

		// Goroutine 2: Put a new value
		go func() {
			defer wg.Done()
			lkv.Put(ctx, key, "new-value")
		}()

		wg.Wait()

		// Check: leasing cache vs direct etcd
		resp, _ := lkv.Get(ctx, key)
		directResp, _ := cli.Get(ctx, key)

		if len(resp.Kvs) != len(directResp.Kvs) {
			fmt.Printf("BUG at iteration %d: leasing cache says %d kvs, etcd says %d kvs\n",
				iter, len(resp.Kvs), len(directResp.Kvs))
			bugFound = true
			break
		}
	}

	if bugFound {
		fmt.Println("BUG_DETECTED")
		os.Exit(1)
	} else {
		fmt.Println("No bug detected in 1000 iterations")
		os.Exit(0)
	}
}
GOEOF

# Run the test from the etcd repo directory (so module resolution works)
echo "Running leasing linearizability test..."
cd "$WORK_DIR"
OUTPUT=$(go run "$TEST_FILE" 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

# Cleanup
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null
rm -rf "$DATA_DIR"
rm -f "$TEST_FILE"

echo ""
if echo "$OUTPUT" | grep -q "BUG_DETECTED"; then
    echo "FAIL: Bug is present — leasing cache returned stale data (mismatch with etcd)"
    exit 1
else
    echo "PASS: Bug is fixed — leasing cache remained consistent with etcd across 1000 iterations"
    exit 0
fi
