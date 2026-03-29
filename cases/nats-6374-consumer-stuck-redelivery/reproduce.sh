#!/usr/bin/env bash
# Reproduction and verification script for nats-6374-consumer-stuck-redelivery
# Injects two tests from the fix PR into the buggy codebase, runs them, and reports PASS/FAIL.
# Test 1: Consumer stuck after leader step-down with inflight ack (o.awl not reset)
# Test 2: Consumer slowdown when redelivering a deleted message (pending/rdc not cleaned)
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-6374-consumer-stuck-redelivery"
TEST_FILE="server/jetstream_consumer_test.go"
TEST1_NAME="TestJetStreamConsumerSwitchLeaderDuringInflightAck"
TEST2_NAME="TestJetStreamConsumerMessageDeletedDuringRedelivery"

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -f "$WORK_DIR/nats-server" ]; then
    echo "ERROR: Binary not found at $WORK_DIR/nats-server. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing nats-6374-consumer-stuck-redelivery ==="

cleanup() {
    [ -f "${TEST_FILE}.bak" ] && mv "${TEST_FILE}.bak" "$TEST_FILE"
}
trap cleanup EXIT

# Back up the original test file and inject tests only if not already present
cp "$TEST_FILE" "${TEST_FILE}.bak"

NEED_INJECT=true
if grep -q "$TEST1_NAME" "$TEST_FILE" && grep -q "$TEST2_NAME" "$TEST_FILE"; then
    NEED_INJECT=false
fi

if $NEED_INJECT; then
# Append both test functions from the fix PR
cat >> "$TEST_FILE" << 'TESTEOF'

func TestJetStreamConsumerSwitchLeaderDuringInflightAck(t *testing.T) {
	s := RunBasicJetStreamServer(t)
	defer s.Shutdown()

	nc, js := jsClientConnect(t, s)
	defer nc.Close()

	_, err := js.AddStream(&nats.StreamConfig{
		Name:     "TEST",
		Subjects: []string{"foo"},
	})
	require_NoError(t, err)

	for i := 0; i < 2_000; i++ {
		_, err = js.Publish("foo", nil)
		require_NoError(t, err)
	}

	sub, err := js.PullSubscribe(
		"foo",
		"CONSUMER",
		nats.MaxAckPending(2_000),
		nats.ManualAck(),
		nats.AckExplicit(),
		nats.AckWait(2*time.Second),
	)
	require_NoError(t, err)

	acc, err := s.lookupAccount(globalAccountName)
	require_NoError(t, err)
	mset, err := acc.lookupStream("TEST")
	require_NoError(t, err)
	o := mset.lookupConsumer("CONSUMER")
	require_NotNil(t, o)

	msgs, err := sub.Fetch(2_000)
	require_NoError(t, err)
	require_Len(t, len(msgs), 2_000)

	// Simulate an ack being pushed, and o.setLeader(false) being called before the ack is processed and resets o.awl
	atomic.AddInt64(&o.awl, 1)
	o.setLeader(false)
	o.setLeader(true)

	msgs, err = sub.Fetch(1, nats.MaxWait(5*time.Second))
	require_NoError(t, err)
	require_Len(t, len(msgs), 1)
}

func TestJetStreamConsumerMessageDeletedDuringRedelivery(t *testing.T) {
	storageTypes := []nats.StorageType{nats.MemoryStorage, nats.FileStorage}
	for _, storageType := range storageTypes {
		t.Run(storageType.String(), func(t *testing.T) {
			s := RunBasicJetStreamServer(t)
			defer s.Shutdown()

			nc, js := jsClientConnect(t, s)
			defer nc.Close()

			_, err := js.AddStream(&nats.StreamConfig{
				Name:     "TEST",
				Subjects: []string{"foo"},
				Storage:  storageType,
			})
			require_NoError(t, err)

			for i := 0; i < 3; i++ {
				_, err = js.Publish("foo", nil)
				require_NoError(t, err)
			}

			sub, err := js.PullSubscribe(
				"foo",
				"CONSUMER",
				nats.ManualAck(),
				nats.AckExplicit(),
				nats.AckWait(time.Second),
			)
			require_NoError(t, err)

			acc, err := s.lookupAccount(globalAccountName)
			require_NoError(t, err)
			mset, err := acc.lookupStream("TEST")
			require_NoError(t, err)
			o := mset.lookupConsumer("CONSUMER")
			require_NotNil(t, o)

			msgs, err := sub.Fetch(3)
			require_NoError(t, err)
			require_Len(t, len(msgs), 3)

			err = js.DeleteMsg("TEST", 2)
			require_NoError(t, err)

			o.mu.Lock()
			defer o.mu.Unlock()
			for seq := range o.rdc {
				o.removeFromRedeliverQueue(seq)
			}

			o.pending = make(map[uint64]*Pending)
			o.pending[2] = &Pending{}
			o.addToRedeliverQueue(2)

			_, _, err = o.getNextMsg()
			require_Error(t, err, ErrStoreEOF)
			require_Len(t, len(o.pending), 0)
			require_Len(t, len(o.rdc), 0)
		})
	}
}
TESTEOF
fi

# Run both tests
echo "Running test $TEST1_NAME..."
TEST1_OUTPUT=$(go test -v -run "$TEST1_NAME" -count=1 -timeout 120s ./server/ 2>&1) || true
echo "$TEST1_OUTPUT" | tail -20

echo ""
echo "Running test $TEST2_NAME..."
TEST2_OUTPUT=$(go test -v -run "$TEST2_NAME" -count=1 -timeout 120s ./server/ 2>&1) || true
echo "$TEST2_OUTPUT" | tail -20

# Restore original file
mv "${TEST_FILE}.bak" "$TEST_FILE"
trap - EXIT

echo ""

# Check results — both tests must fail (bug present) or both pass (bug fixed)
TEST1_PASS=false
TEST2_PASS=false
if echo "$TEST1_OUTPUT" | grep -q "^--- PASS:"; then
    TEST1_PASS=true
fi
if echo "$TEST2_OUTPUT" | grep -q "^--- PASS:"; then
    TEST2_PASS=true
fi

if $TEST1_PASS && $TEST2_PASS; then
    echo "PASS: Bug is fixed — both consumer stuck and redelivery cleanup tests passed"
    exit 0
else
    echo "FAIL: Bug is present —"
    if ! $TEST1_PASS; then
        echo "  - $TEST1_NAME failed (o.awl not reset on leader step-down)"
    fi
    if ! $TEST2_PASS; then
        echo "  - $TEST2_NAME failed (deleted messages not cleaned from pending/rdc)"
    fi
    exit 1
fi
