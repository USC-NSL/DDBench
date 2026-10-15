#!/usr/bin/env bash
# Reproduction and verification script for rocksdb-10751-stalled-writes-shutdown
# Builds the harness test_stall_shutdown.cc (shipped with this case, never placed
# in the worktree) against the worktree's include/ and build/librocksdb.a, then
# runs it: a writer blocked in a write stop (L0 file count at
# level0_stop_writes_trigger, compaction slowed by a rate limiter) must return
# when the DB is shut down instead of blocking forever.
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

LIB="$WORK_DIR/build/librocksdb.a"
HARNESS="$RUN_DIR/test_stall_shutdown"

rebuild_worktree
[ -f "$LIB" ] || error "librocksdb.a not found at $LIB (run setup first)"
[ -f "$CASE_DIR/test_stall_shutdown.cc" ] || error "harness $CASE_DIR/test_stall_shutdown.cc missing"

echo "=== Reproducing rocksdb-10751-stalled-writes-shutdown ==="

echo "Building the harness against the worktree's librocksdb.a ..."
if ! g++ -std=c++17 -O1 -include cstdint -w -I"$WORK_DIR/include" \
        "$CASE_DIR/test_stall_shutdown.cc" "$LIB" \
        -lpthread -ldl -lsnappy -lz -lbz2 -llz4 -lzstd -luring -lgflags \
        -o "$HARNESS" > "$RUN_DIR/build.log" 2>&1; then
    tail -30 "$RUN_DIR/build.log"
    fail "the harness does not compile/link against the worktree's RocksDB"
fi

# The harness prints its own PASS/FAIL/ERROR line and follows the exit-code
# contract (0 PASS, 1 FAIL, 2 ERROR).
timeout 300 "$HARNESS" "$RUN_DIR/db"
rc=$?
case "$rc" in
    0|1|2) exit "$rc" ;;
    124)   fail "Bug is present — the harness hung for 300s" ;;
    *)     fail "the harness crashed (exit $rc)" ;;
esac
