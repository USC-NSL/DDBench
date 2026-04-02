#!/usr/bin/env bash
# Reproduction and verification script for nats-7852-filter-perf
# Extracts the test from the fix commit, runs it on the buggy version, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7852-filter-perf"
TEST_FILE="server/jetstream_consumer_test.go"
TEST_NAME="TestJetStreamConsumerSingleFilterSubjectInFilterSubjects"

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -f "$WORK_DIR/nats-server" ]; then
    echo "ERROR: Binary not found at $WORK_DIR/nats-server. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing nats-7852-filter-perf ==="

cleanup() {
    [ -f "${TEST_FILE}.bak" ] && mv "${TEST_FILE}.bak" "$TEST_FILE"
}
trap cleanup EXIT

# Back up the original test file
cp "$TEST_FILE" "${TEST_FILE}.bak"

# Inline the behavioral test function.
# Verifies that a consumer with a single FilterSubjects entry does not
# initialize the sublist/filters (which would activate the slow per-message
# filtering path). On buggy code: filters is non-nil → test FAILS
# On fixed code: filters is nil, subjf has 1 entry → test PASSES
if ! grep -q "func ${TEST_NAME}" "$TEST_FILE"; then
cat >> "$TEST_FILE" << 'TESTEOF'

func TestJetStreamConsumerSingleFilterSubjectInFilterSubjects(t *testing.T) {
	s := RunBasicJetStreamServer(t)
	defer s.Shutdown()

	nc, js := jsClientConnect(t, s)
	defer nc.Close()

	_, err := js.AddStream(&nats.StreamConfig{
		Name:     "TEST",
		Subjects: []string{"foo"},
	})
	require_NoError(t, err)

	// Publish messages for functional verification.
	for i := 0; i < 5; i++ {
		_, err = js.Publish("foo", []byte("msg"))
		require_NoError(t, err)
	}

	// Consumer A: scalar FilterSubject (always uses optimized single-subject path).
	_, err = js.AddConsumer("TEST", &nats.ConsumerConfig{
		Durable:       "SCALAR",
		FilterSubject: "foo",
	})
	require_NoError(t, err)

	// Consumer B: single-element FilterSubjects array (should be equivalent to A).
	_, err = js.AddConsumer("TEST", &nats.ConsumerConfig{
		Durable:        "ARRAY",
		FilterSubjects: []string{"foo"},
	})
	require_NoError(t, err)

	mset, err := s.globalAccount().lookupStream("TEST")
	require_NoError(t, err)

	scalar := mset.lookupConsumer("SCALAR")
	require_NotNil(t, scalar)
	array := mset.lookupConsumer("ARRAY")
	require_NotNil(t, array)

	// Compare internal filter state: both consumers should use the fast
	// LoadNextMsg path (filters == nil), not the slow LoadNextMsgMulti path.
	scalar.mu.RLock()
	scalarHasFilters := scalar.filters != nil
	scalar.mu.RUnlock()

	array.mu.RLock()
	arrayHasFilters := array.filters != nil
	arraySubjfLen := len(array.subjf)
	array.mu.RUnlock()

	require_Len(t, arraySubjfLen, 1)

	// On buggy code: scalar.filters is nil (fast path) but array.filters is
	// non-nil (slow LoadNextMsgMulti path), so the equivalence check fails.
	// On fixed code: both are nil — FilterSubjects:["foo"] is normalized to
	// use the same optimized path as FilterSubject:"foo".
	if scalarHasFilters != arrayHasFilters {
		t.Fatalf("FilterSubjects:[\"foo\"] and FilterSubject:\"foo\" should produce "+
			"equivalent consumers, but filter initialization differs: "+
			"scalar filters initialized=%v, array filters initialized=%v. "+
			"Single-element FilterSubjects incorrectly activates the slow "+
			"multi-filter path (LoadNextMsgMulti instead of LoadNextMsg), "+
			"causing >20%% performance degradation.",
			scalarHasFilters, arrayHasFilters)
	}
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
