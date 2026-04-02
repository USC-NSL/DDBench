#!/usr/bin/env bash
# Reproduction and verification script for nats-7817-workqueue-message-loss
# Extracts the test from the fix commit, runs it on the buggy version, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7817-workqueue-message-loss"
TEST_FILE="server/jetstream_test.go"
TEST_NAME="TestJetStreamWQMaxDeliveryReached"

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -f "$WORK_DIR/nats-server" ]; then
    echo "ERROR: Binary not found at $WORK_DIR/nats-server. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing nats-7817-workqueue-message-loss ==="

cleanup() {
    [ -f "${TEST_FILE}.bak" ] && mv "${TEST_FILE}.bak" "$TEST_FILE"
}
trap cleanup EXIT

# Back up the original test file
cp "$TEST_FILE" "${TEST_FILE}.bak"

# Inline the behavioral test function.
# Verifies that messages reaching max-deliver in a WorkQueue stream are
# NOT incorrectly removed. Publishes messages, lets them hit max delivery,
# then checks that the stream still contains the undelivered messages.
# On buggy code: messages silently lost → test FAILS
# On fixed code: messages retained → test PASSES
if ! grep -q "func ${TEST_NAME}" "$TEST_FILE"; then
cat >> "$TEST_FILE" << 'TESTEOF'

func TestJetStreamWQMaxDeliveryReached(t *testing.T) {
	c := createJetStreamClusterExplicit(t, "R3S", 3)
	defer c.shutdown()

	nc, js := jsClientConnect(t, c.randomServer())
	defer nc.Close()

	_, err := js.AddStream(&nats.StreamConfig{
		Name:      "TEST",
		Subjects:  []string{"foo"},
		Replicas:  3,
		Retention: nats.WorkQueuePolicy,
	})
	require_NoError(t, err)

	for range 3 {
		_, err = js.Publish("foo", nil)
		require_NoError(t, err)
	}

	sub, err := js.PullSubscribe(_EMPTY_, "CONSUMER",
		nats.BindStream("TEST"),
		nats.MaxDeliver(2),
		nats.AckExplicit(),
		nats.AckWait(200*time.Millisecond),
	)
	require_NoError(t, err)
	defer sub.Drain()

	msgs, err := sub.Fetch(3, nats.MaxWait(time.Second))
	require_NoError(t, err)
	require_Len(t, len(msgs), 3)

	msgs, err = sub.Fetch(3, nats.MaxWait(time.Second))
	require_NoError(t, err)
	require_Len(t, len(msgs), 3)

	_, err = sub.Fetch(1, nats.MaxWait(500*time.Millisecond))
	require_Error(t, err, nats.ErrTimeout)

	_, err = js.Publish("foo", nil)
	require_NoError(t, err)
	msgs, err = sub.Fetch(1, nats.MaxWait(500*time.Millisecond))
	require_NoError(t, err)
	require_Len(t, len(msgs), 1)
	require_NoError(t, msgs[0].AckSync())

	cl := c.consumerLeader(globalAccountName, "TEST", "CONSUMER")
	require_NotNil(t, cl)
	mset, err := cl.globalAccount().lookupStream("TEST")
	require_NoError(t, err)
	o := mset.lookupConsumer("CONSUMER")
	require_NotNil(t, o)
	o.mu.RLock()
	pending, rdc, adflr, asflr := len(o.pending), len(o.rdc), o.adflr, o.asflr
	o.mu.RUnlock()
	require_Equal(t, pending, 0)
	require_Equal(t, rdc, 3)
	require_Equal(t, adflr, 7)
	require_Equal(t, asflr, 4)

	mset.checkInterestState()
	time.Sleep(200 * time.Millisecond)
	checkFor(t, 2*time.Second, 200*time.Millisecond, func() error {
		return checkState(t, c, globalAccountName, "TEST")
	})

	sm, err := mset.store.LoadMsg(1, nil)
	require_NoError(t, err)
	require_Equal(t, sm.subj, "foo")
}
TESTEOF
fi

# Run the test
echo "Running test $TEST_NAME..."
TEST_OUTPUT=$(go test -v -run "$TEST_NAME" -count=1 -timeout 120s ./server/ 2>&1) || true
TEST_EXIT=$?

echo "$TEST_OUTPUT" | tail -20

# Restore original file
mv "${TEST_FILE}.bak" "$TEST_FILE"

echo ""
if echo "$TEST_OUTPUT" | grep -q "^--- PASS:"; then
    echo "PASS: Bug is fixed — $TEST_NAME passed"
    exit 0
else
    echo "FAIL: Bug is present — $TEST_NAME failed"
    exit 1
fi
