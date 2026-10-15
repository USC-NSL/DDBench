#!/usr/bin/env bash
# Reproduction and verification script for nats-7760-filter-stepdown
# Starts a 5-node NATS cluster from the worktree's nats-server, creates an
# interest-based R5 stream and a pull consumer with two filter subjects, checks
# delivery, edits the filter set (keeping one subject, replacing the other),
# steps the consumer leader down, publishes to the kept subject, and checks that
# the consumer still receives it. Uses the pinned nats CLI from the image
# (docker/nats.Dockerfile).
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

BINARY="$WORK_DIR/nats-server"
DATA_DIR="$RUN_DIR/data"

rebuild_worktree
[ -x "$BINARY" ] || error "nats-server binary not found at $BINARY (run setup first)"
# The nats CLI is pinned in the bug-bench/nats image, outside the worktree.
NATS_CLI="$(command -v nats)" || error "nats CLI not found in the image (rebuild bug-bench/nats)"
echo "Using $NATS_CLI ($("$NATS_CLI" --version 2>&1))"

echo "=== Reproducing nats-7760-filter-stepdown ==="

PIDS=()
cleanup() {
    local p
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
    for p in "${PIDS[@]}"; do wait "$p" 2>/dev/null; done
}
trap cleanup EXIT

mkdir -p "$DATA_DIR"
for i in 1 2 3 4 5; do
cat > "$DATA_DIR/n${i}.conf" <<CONF
port: $((4320 + i))
http: $((8320 + i))
server_name: n${i}
jetstream {
  store_dir: ${DATA_DIR}/n${i}
  max_mem: 64MB
  max_file: 256MB
}
cluster {
  name: ddbench-cluster
  listen: 127.0.0.1:$((6320 + i))
  routes: [
    nats-route://127.0.0.1:6321
    nats-route://127.0.0.1:6322
    nats-route://127.0.0.1:6323
    nats-route://127.0.0.1:6324
    nats-route://127.0.0.1:6325
  ]
}
CONF
done

echo "Starting 5-node NATS cluster..."
for i in 1 2 3 4 5; do
    "$BINARY" -c "$DATA_DIR/n${i}.conf" > "$DATA_DIR/n${i}.log" 2>&1 &
    PIDS+=($!)
done
for i in 1 2 3 4 5; do
    ok=false
    for _ in $(seq 1 60); do
        if curl -fs "http://127.0.0.1:$((8320 + i))/healthz" >/dev/null 2>&1; then ok=true; break; fi
        sleep 0.5
    done
    [ "$ok" = true ] || { tail -5 "$DATA_DIR/n${i}.log"; fail "server n${i} did not become healthy"; }
done

export NATS_URL="nats://127.0.0.1:4321"
# Every CLI call is bounded: a call that waits on the cluster forever must not
# hang the oracle.
nats_() { timeout 60 "$NATS_CLI" "$@" </dev/null; }
consumer_leader() { nats_ consumer info ORDERS processor --json 2>/dev/null | grep -m1 -o '"leader": *"[^"]*"'; }

echo "Creating interest-based R5 stream ORDERS (orders.>)..."
created=false
for _ in $(seq 1 20); do
    if nats_ stream add ORDERS --subjects="orders.>" --retention=interest --replicas=5 \
            --storage=file --defaults >/dev/null 2>"$RUN_DIR/err"; then created=true; break; fi
    sleep 1
done
[ "$created" = true ] || { cat "$RUN_DIR/err"; error "could not create the R5 stream (trigger not established)"; }

echo "Creating pull consumer processor (filters orders.new, orders.paid)..."
# Retried like the stream: an R5 consumer create can time out while the
# freshly formed cluster is still settling (adding an identical consumer again
# is idempotent).
created=false
for _ in $(seq 1 10); do
    if nats_ consumer add ORDERS processor --pull --filter orders.new --filter orders.paid --deliver all \
            --ack explicit --replay instant --max-deliver 20 --max-pending 1000 --defaults >/dev/null 2>"$RUN_DIR/err"; then
        created=true; break
    fi
    sleep 2
done
[ "$created" = true ] || { cat "$RUN_DIR/err"; error "could not create the consumer"; }

# On an interest stream a message published before the new consumer's interest
# is registered everywhere is simply not retained, so retry the sanity check.
echo "Sanity check: delivery before the filter edit..."
sleep 2
delivered=false
for attempt in 1 2 3 4 5; do
    nats_ pub orders.new "before-edit-$attempt" >/dev/null 2>&1 || fail "publish failed"
    OUT=$(nats_ consumer next ORDERS processor --count 1 --timeout 5s 2>&1)
    if printf '%s\n' "$OUT" | grep -q "before-edit"; then delivered=true; break; fi
    sleep 2
done
[ "$delivered" = true ] || { echo "$OUT"; fail "the consumer does not deliver even before the filter edit"; }

echo "Editing the consumer filters to orders.new, orders.shipped..."
nats_ consumer edit ORDERS processor --filter orders.new --filter orders.shipped --force >/dev/null 2>"$RUN_DIR/err" \
    || { cat "$RUN_DIR/err"; error "could not edit the consumer filters"; }
nats_ consumer info ORDERS processor --json 2>/dev/null | grep -q '"orders.shipped"' \
    || error "the consumer filters were not updated"
sleep 1

LEADER_BEFORE=$(consumer_leader)
echo "Stepping down the consumer leader (${LEADER_BEFORE:-unknown})..."
stepped=false
for _ in 1 2 3; do
    if timeout 30 "$NATS_CLI" consumer cluster step-down ORDERS processor </dev/null >/dev/null 2>"$RUN_DIR/err"; then
        stepped=true; break
    fi
    sleep 2
done
[ "$stepped" = true ] || { cat "$RUN_DIR/err"; error "consumer leader step-down failed or timed out"; }
LEADER_AFTER=""
for _ in $(seq 1 20); do
    LEADER_AFTER=$(consumer_leader)
    [ -n "$LEADER_AFTER" ] && [ "$LEADER_AFTER" != "$LEADER_BEFORE" ] && break
    sleep 0.5
done
[ -n "$LEADER_AFTER" ] && [ "$LEADER_AFTER" != "$LEADER_BEFORE" ] \
    || error "the consumer leader did not change after step-down (trigger not established)"
echo "New consumer leader: $LEADER_AFTER"
sleep 1

echo "Publishing to orders.new (still a filter subject)..."
nats_ pub orders.new "ddbench-probe-message" >/dev/null 2>"$RUN_DIR/err" \
    || { cat "$RUN_DIR/err"; fail "publish to orders.new failed"; }
sleep 1

echo "Fetching from the consumer..."
OUTPUT=$(nats_ consumer next ORDERS processor --count 5 --timeout 5s 2>&1)
echo "$OUTPUT" | tail -5
if printf '%s\n' "$OUTPUT" | grep -q "ddbench-probe-message"; then
    pass "Bug is fixed — the consumer still receives matching messages after the filter edit and leader step-down"
fi
fail "Bug is present — the consumer did not receive a matching message after the filter edit and leader step-down"
