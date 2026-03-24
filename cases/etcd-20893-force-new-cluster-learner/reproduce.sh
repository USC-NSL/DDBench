#!/usr/bin/env bash
# Reproduction and verification script for etcd-20893-force-new-cluster-learner
# Starts a 3-member cluster, adds a learner, triggers snapshot, recovers with
# --force-new-cluster, and checks if the learner is still in the member list.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/etcd-20893-force-new-cluster-learner"
ETCD="$WORK_DIR/bin/etcd"
ETCDCTL="$WORK_DIR/bin/etcdctl"
DATA_DIR="$WORK_DIR/etcd-20893-data"

export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$ETCD" ]; then
    echo "ERROR: Binary not found at $ETCD. Run ./setup.sh first."
    exit 1
fi
if [ ! -x "$ETCDCTL" ]; then
    echo "ERROR: Binary not found at $ETCDCTL. Run ./setup.sh first."
    exit 1
fi

# Cleanup from previous runs
pkill -f "etcd.*etcd-20893" 2>/dev/null || true
sleep 2
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"

echo "=== Reproducing etcd-20893-force-new-cluster-learner ==="

cleanup() {
    [ -n "${M1_PID:-}" ] && kill "$M1_PID" 2>/dev/null && wait "$M1_PID" 2>/dev/null
    [ -n "${M2_PID:-}" ] && kill "$M2_PID" 2>/dev/null && wait "$M2_PID" 2>/dev/null
    [ -n "${M3_PID:-}" ] && kill "$M3_PID" 2>/dev/null && wait "$M3_PID" 2>/dev/null
    [ -n "${RECOVERED_PID:-}" ] && kill "$RECOVERED_PID" 2>/dev/null && wait "$RECOVERED_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
}
trap cleanup EXIT

# Step 1: Start a 3-member cluster with low snapshot count
echo "Starting 3-member etcd cluster..."

"$ETCD" --name m1 \
  --data-dir "$DATA_DIR/m1" \
  --listen-client-urls http://127.0.0.1:12379 \
  --advertise-client-urls http://127.0.0.1:12379 \
  --listen-peer-urls http://127.0.0.1:12380 \
  --initial-advertise-peer-urls http://127.0.0.1:12380 \
  --initial-cluster "m1=http://127.0.0.1:12380,m2=http://127.0.0.1:12382,m3=http://127.0.0.1:12384" \
  --initial-cluster-token test-20893 \
  --snapshot-count=2 &>/dev/null &
M1_PID=$!

"$ETCD" --name m2 \
  --data-dir "$DATA_DIR/m2" \
  --listen-client-urls http://127.0.0.1:12381 \
  --advertise-client-urls http://127.0.0.1:12381 \
  --listen-peer-urls http://127.0.0.1:12382 \
  --initial-advertise-peer-urls http://127.0.0.1:12382 \
  --initial-cluster "m1=http://127.0.0.1:12380,m2=http://127.0.0.1:12382,m3=http://127.0.0.1:12384" \
  --initial-cluster-token test-20893 \
  --snapshot-count=2 &>/dev/null &
M2_PID=$!

"$ETCD" --name m3 \
  --data-dir "$DATA_DIR/m3" \
  --listen-client-urls http://127.0.0.1:12383 \
  --advertise-client-urls http://127.0.0.1:12383 \
  --listen-peer-urls http://127.0.0.1:12384 \
  --initial-advertise-peer-urls http://127.0.0.1:12384 \
  --initial-cluster "m1=http://127.0.0.1:12380,m2=http://127.0.0.1:12382,m3=http://127.0.0.1:12384" \
  --initial-cluster-token test-20893 \
  --snapshot-count=2 &>/dev/null &
M3_PID=$!

sleep 15

# Verify cluster is healthy
if ! "$ETCDCTL" --endpoints=http://127.0.0.1:12379 endpoint health &>/dev/null; then
    echo "ERROR: Cluster failed to start."
    kill $M1_PID $M2_PID $M3_PID 2>/dev/null
    wait $M1_PID $M2_PID $M3_PID 2>/dev/null
    rm -rf "$DATA_DIR"
    exit 1
fi

# Step 2: Add a learner member (with retry loop)
echo "Adding learner member..."
for attempt in $(seq 1 10); do
    if "$ETCDCTL" --endpoints=http://127.0.0.1:12379 member add learner1 \
      --peer-urls=http://127.0.0.1:12386 \
      --learner 2>/dev/null; then
        echo "Learner added on attempt $attempt"
        break
    fi
    echo "Attempt $attempt failed, retrying in 3s..."
    sleep 3
done

# Step 3: Write enough keys to trigger a snapshot
echo "Writing keys to trigger snapshot..."
for i in $(seq 1 10); do
  "$ETCDCTL" --endpoints=http://127.0.0.1:12379 put "key$i" "val$i" &>/dev/null
done
sleep 3

# Step 4: Stop all members
echo "Stopping all members..."
kill $M1_PID $M2_PID $M3_PID 2>/dev/null
wait $M1_PID $M2_PID $M3_PID 2>/dev/null
sleep 2

# Step 5: Restart member 1 with --force-new-cluster
echo "Restarting m1 with --force-new-cluster..."
"$ETCD" --name m1 \
  --data-dir "$DATA_DIR/m1" \
  --listen-client-urls http://127.0.0.1:12379 \
  --advertise-client-urls http://127.0.0.1:12379 \
  --listen-peer-urls http://127.0.0.1:12380 \
  --initial-advertise-peer-urls http://127.0.0.1:12380 \
  --force-new-cluster &>/dev/null &
RECOVERED_PID=$!
sleep 5

# Verify recovered node is healthy
if ! kill -0 "$RECOVERED_PID" 2>/dev/null; then
    echo "ERROR: Recovered etcd failed to start."
    rm -rf "$DATA_DIR"
    exit 1
fi

# Step 6: Check the member list
echo "Checking member list..."
MEMBER_OUTPUT=$("$ETCDCTL" --endpoints=http://127.0.0.1:12379 member list 2>&1)
echo "$MEMBER_OUTPUT"

MEMBER_COUNT=$(echo "$MEMBER_OUTPUT" | grep -c "," || true)
HAS_LEARNER=$(echo "$MEMBER_OUTPUT" | grep -ci "learner" || true)

# Cleanup
kill "$RECOVERED_PID" 2>/dev/null
wait "$RECOVERED_PID" 2>/dev/null
rm -rf "$DATA_DIR"

echo ""
if [ "$HAS_LEARNER" -gt 0 ] || [ "$MEMBER_COUNT" -gt 1 ]; then
    echo "FAIL: Bug is present — learner still in member list after --force-new-cluster (found $MEMBER_COUNT members, $HAS_LEARNER learner entries)"
    exit 1
else
    echo "PASS: Bug is fixed — only m1 in member list after --force-new-cluster"
    exit 0
fi
