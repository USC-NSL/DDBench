#!/usr/bin/env bash
# Reproduction and verification script for etcd-20704-leasing-linearizability
# Starts a single-node etcd from the worktree and runs a client program (built
# against the worktree's client/v3/leasing) that races Delete and Put on one key
# through a leasing KV, 1000 times, comparing the leasing cache with etcd.
#
# Exit codes: 0 = PASS (bug fixed), 1 = FAIL (bug present, or the worktree does
# not build / the code under test does not start), 2 = ERROR (oracle or
# infrastructure problem; the verdict is inconclusive).
# ── Runs only inside the bench.sh reproduce container (BENCH_WORKDIR is set) ──
if [ -z "${BENCH_WORKDIR:-}" ]; then
    CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    [ -f "$REPO_ROOT/bench.sh" ] && exec bash "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
    echo "ERROR: run this oracle with ./bench.sh reproduce $CASE_NAME" >&2
    exit 2
fi
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$BENCH_WORKDIR"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ddbench.XXXXXX")"   # scratch space outside the worktree

pass()  { echo ""; echo "PASS: $*"; exit 0; }
fail()  { echo ""; echo "FAIL: $*"; exit 1; }
error() { echo ""; echo "ERROR: $*"; exit 2; }

# REBUILD.sh is the worktree's designated build entry point.
rebuild_worktree() {
    [ -f "$WORK_DIR/REBUILD.sh" ] || error "REBUILD.sh not found in $WORK_DIR (run setup first)"
    bash "$WORK_DIR/REBUILD.sh" || fail "the worktree does not build (REBUILD.sh exited non-zero)"
}

BINARY="$WORK_DIR/bin/etcd"
DATA_DIR="$RUN_DIR/data"
CLIENT_PORT=22379
PEER_PORT=22380
ORACLE_SRC="$WORK_DIR/zz_ddbench_oracle_main.go"
ORACLE_BIN="$RUN_DIR/leasing-oracle"


rebuild_worktree
[ -x "$BINARY" ] || error "etcd binary not found at $BINARY (run setup first)"

echo "=== Reproducing etcd-20704-leasing-linearizability ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    rm -f "$ORACLE_SRC"
}
trap cleanup EXIT

"$BINARY" --data-dir "$DATA_DIR" \
    --listen-client-urls "http://127.0.0.1:$CLIENT_PORT" --advertise-client-urls "http://127.0.0.1:$CLIENT_PORT" \
    --listen-peer-urls "http://127.0.0.1:$PEER_PORT" --initial-advertise-peer-urls "http://127.0.0.1:$PEER_PORT" \
    --initial-cluster "default=http://127.0.0.1:$PEER_PORT" > "$RUN_DIR/etcd.log" 2>&1 &
SERVER_PID=$!
ready=false
for _ in $(seq 1 60); do
    kill -0 "$SERVER_PID" 2>/dev/null || break
    if "$WORK_DIR/bin/etcdctl" --endpoints="http://127.0.0.1:$CLIENT_PORT" endpoint health >/dev/null 2>&1; then
        ready=true; break
    fi
    sleep 0.5
done
if [ "$ready" != true ]; then
    tail -20 "$RUN_DIR/etcd.log"
    fail "etcd did not start serving"
fi

# The client program lives in the worktree only while it is being compiled (it
# must resolve go.etcd.io/etcd/client/v3 to the worktree's module).
cat > "$ORACLE_SRC" << 'GOEOF'
//go:build ignore

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

// Exit codes: 0 consistent, 1 inconsistency found, 3 a leasing KV operation
// failed, 5 could not connect to etcd.
func main() {
	cli, err := clientv3.New(clientv3.Config{
		Endpoints:   []string{os.Args[1]},
		DialTimeout: 5 * time.Second,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "CONNECT_ERROR: %v\n", err)
		os.Exit(5)
	}
	defer cli.Close()

	lkv, closeFn, err := leasing.NewKV(cli, "leasing-test/")
	if err != nil {
		fmt.Printf("OP_ERROR: creating the leasing KV: %v\n", err)
		os.Exit(3)
	}
	if closeFn != nil {
		defer closeFn()
	}

	ctx := context.Background()
	key := "/test/leasing-key"
	opErr := func(what string, err error) {
		fmt.Printf("OP_ERROR: %s: %v\n", what, err)
		os.Exit(3)
	}

	for iter := 0; iter < 1000; iter++ {
		if _, err := lkv.Put(ctx, key, "initial"); err != nil {
			opErr("put", err)
		}

		var wg sync.WaitGroup
		var delErr, putErr error
		wg.Add(2)
		go func() {
			defer wg.Done()
			_, delErr = lkv.Delete(ctx, key)
		}()
		go func() {
			defer wg.Done()
			_, putErr = lkv.Put(ctx, key, "new-value")
		}()
		wg.Wait()
		if delErr != nil {
			opErr("concurrent delete", delErr)
		}
		if putErr != nil {
			opErr("concurrent put", putErr)
		}

		resp, err := lkv.Get(ctx, key)
		if err != nil {
			opErr("leasing get", err)
		}
		directResp, err := cli.Get(ctx, key)
		if err != nil {
			opErr("direct get", err)
		}
		if len(resp.Kvs) != len(directResp.Kvs) {
			fmt.Printf("INCONSISTENT at iteration %d: leasing cache returns %d kvs, etcd returns %d kvs\n",
				iter, len(resp.Kvs), len(directResp.Kvs))
			os.Exit(1)
		}
	}
	fmt.Println("CONSISTENT: 1000 iterations")
	os.Exit(0)
}
GOEOF

cd "$WORK_DIR"
if ! go build -o "$ORACLE_BIN" "$ORACLE_SRC" > "$RUN_DIR/build.log" 2>&1; then
    cat "$RUN_DIR/build.log"
    if grep -qE 'dial tcp|i/o timeout|TLS handshake timeout|no such host' "$RUN_DIR/build.log"; then
        error "could not download Go modules for the client program (network)"
    fi
    fail "the client program does not compile against the worktree's client/v3/leasing"
fi
rm -f "$ORACLE_SRC"

echo "Running the leasing Delete+Put race check ..."
timeout 300 "$ORACLE_BIN" "http://127.0.0.1:$CLIENT_PORT" > "$RUN_DIR/oracle.out" 2>&1
rc=$?
cat "$RUN_DIR/oracle.out"
case "$rc" in
    0)   grep -qx "CONSISTENT: 1000 iterations" "$RUN_DIR/oracle.out" \
             && pass "Bug is fixed — the leasing cache stayed consistent with etcd across 1000 iterations"
         error "the client program exited 0 without completing" ;;
    1)   fail "Bug is present — the leasing cache disagrees with etcd after a concurrent Delete and Put" ;;
    3)   fail "a leasing KV operation failed (see output above)" ;;
    5)   error "the client program could not connect to etcd" ;;
    124) fail "the client program hung for 300s" ;;
    *)   fail "the client program crashed (exit $rc)" ;;
esac
