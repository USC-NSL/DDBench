#!/usr/bin/env bash
# Reproduction and verification script for etcd-20893-force-new-cluster-learner
# Starts a 3-member etcd cluster with a low snapshot count, adds a learner,
# writes enough keys to trigger a snapshot, stops everything, restarts member 1
# with --force-new-cluster, and checks that only member 1 remains.
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

ETCD="$WORK_DIR/bin/etcd"
ETCDCTL="$WORK_DIR/bin/etcdctl"
DATA_DIR="$RUN_DIR/data"
CLUSTER="m1=http://127.0.0.1:12380,m2=http://127.0.0.1:12382,m3=http://127.0.0.1:12384"
EP=http://127.0.0.1:12379


rebuild_worktree
[ -x "$ETCD" ] || error "etcd binary not found at $ETCD (run setup first)"
[ -x "$ETCDCTL" ] || error "etcdctl binary not found at $ETCDCTL (run setup first)"

echo "=== Reproducing etcd-20893-force-new-cluster-learner ==="

cleanup() {
    local p
    for p in ${M1_PID:-} ${M2_PID:-} ${M3_PID:-} ${RECOVERED_PID:-}; do
        kill "$p" 2>/dev/null && wait "$p" 2>/dev/null
    done
}
trap cleanup EXIT

start_member() {  # <name> <client-port> <peer-port>
    "$ETCD" --name "$1" --data-dir "$DATA_DIR/$1" \
        --listen-client-urls "http://127.0.0.1:$2" --advertise-client-urls "http://127.0.0.1:$2" \
        --listen-peer-urls "http://127.0.0.1:$3" --initial-advertise-peer-urls "http://127.0.0.1:$3" \
        --initial-cluster "$CLUSTER" --initial-cluster-token ddbench-cluster \
        --snapshot-count=2 > "$RUN_DIR/$1.log" 2>&1 &
}

# Step 1: 3-member cluster with a low snapshot count
echo "Starting 3-member etcd cluster..."
start_member m1 12379 12380; M1_PID=$!
start_member m2 12381 12382; M2_PID=$!
start_member m3 12383 12384; M3_PID=$!
healthy=false
for _ in $(seq 1 60); do
    if "$ETCDCTL" --endpoints="$EP" endpoint health >/dev/null 2>&1; then healthy=true; break; fi
    sleep 1
done
[ "$healthy" = true ] || { tail -5 "$RUN_DIR"/m1.log; fail "the 3-member cluster did not become healthy"; }

# Step 2: add a learner (retry while the cluster settles)
echo "Adding learner member..."
added=false
for attempt in $(seq 1 10); do
    if "$ETCDCTL" --endpoints="$EP" member add learner1 --peer-urls=http://127.0.0.1:12386 --learner; then
        added=true; break
    fi
    echo "Attempt $attempt failed, retrying in 3s..."
    sleep 3
done
[ "$added" = true ] || error "could not add the learner member (trigger not established)"
# (An unstarted member is listed without a name; match its peer URL.)
"$ETCDCTL" --endpoints="$EP" member list 2>/dev/null | grep -q "127.0.0.1:12386" \
    || error "the learner is not in the member list after member add"

# Step 3: write enough keys to trigger a snapshot
echo "Writing keys to trigger a snapshot..."
for i in $(seq 1 10); do
    "$ETCDCTL" --endpoints="$EP" put "key$i" "val$i" >/dev/null || fail "put key$i failed"
done
sleep 3

# Step 4: stop all members
echo "Stopping all members..."
kill "$M1_PID" "$M2_PID" "$M3_PID" 2>/dev/null
wait "$M1_PID" "$M2_PID" "$M3_PID" 2>/dev/null
M1_PID= M2_PID= M3_PID=
sleep 2

# Step 5: restart member 1 with --force-new-cluster
echo "Restarting m1 with --force-new-cluster..."
"$ETCD" --name m1 --data-dir "$DATA_DIR/m1" \
    --listen-client-urls "$EP" --advertise-client-urls "$EP" \
    --listen-peer-urls http://127.0.0.1:12380 --initial-advertise-peer-urls http://127.0.0.1:12380 \
    --force-new-cluster > "$RUN_DIR/recovered.log" 2>&1 &
RECOVERED_PID=$!
ok=false
for _ in $(seq 1 30); do
    kill -0 "$RECOVERED_PID" 2>/dev/null || break
    if "$ETCDCTL" --endpoints="$EP" endpoint health >/dev/null 2>&1; then ok=true; break; fi
    sleep 1
done
[ "$ok" = true ] || { tail -20 "$RUN_DIR/recovered.log"; fail "the member restarted with --force-new-cluster did not come up"; }

# Step 6: the member list must contain exactly m1
echo "Checking member list..."
MEMBER_OUTPUT=$("$ETCDCTL" --endpoints="$EP" member list 2>&1) || { echo "$MEMBER_OUTPUT"; fail "member list failed on the recovered member"; }
echo "$MEMBER_OUTPUT"
MEMBER_COUNT=$(printf '%s\n' "$MEMBER_OUTPUT" | grep -c ',')
if [ "$MEMBER_COUNT" -eq 1 ] && printf '%s\n' "$MEMBER_OUTPUT" | grep -q ', m1,'; then
    pass "Bug is fixed — only m1 is in the member list after --force-new-cluster"
fi
fail "Bug is present — the member list after --force-new-cluster still has $MEMBER_COUNT members"
