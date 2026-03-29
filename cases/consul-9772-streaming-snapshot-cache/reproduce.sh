#!/usr/bin/env bash
# Reproduction and verification script for consul-9772-streaming-snapshot-cache
# Injects a test into agent/consul/stream/event_publisher_test.go that exercises
# the snapshot cache after a stale-index resume, then checks if a fresh subscriber
# (Index=0) incorrectly receives a newSnapshotToFollow framing event.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/consul-9772-streaming-snapshot-cache"
TEST_FILE="agent/consul/stream/event_publisher_test.go"
TEST_NAME="TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache"

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

cd "$WORK_DIR"

echo "=== Reproducing consul-9772-streaming-snapshot-cache ==="

INJECTED=false
cleanup() {
    [ "$INJECTED" = true ] && [ -f "${TEST_FILE}.bak" ] && mv "${TEST_FILE}.bak" "$TEST_FILE"
}
trap cleanup EXIT

# Inject the test function (skip if fix commit already includes it).
# This test:
# 1. Creates a publisher with a snapshot handler returning 2 events and cache TTL=1s
# 2. Publishes those events to the topic buffer
# 3. Subscribes with Index=1 (stale), which triggers a snapshot build with
#    newSnapshotToFollow prepended -- this gets cached (the bug)
# 4. Replaces the snapshot handler with one that errors (to prove cache is used)
# 5. Subscribes with Index=0 (fresh) and checks that the first event is NOT
#    newSnapshotToFollow but rather the actual snapshot data
if grep -q "func ${TEST_NAME}" "$TEST_FILE" 2>/dev/null; then
    echo "Test $TEST_NAME already exists in source (fix commit) — skipping injection"
else
    INJECTED=true
    # Back up the original test file
    cp "$TEST_FILE" "${TEST_FILE}.bak"
    cat >> "$TEST_FILE" << 'TESTEOF'

func TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache(t *testing.T) {
	req := &SubscribeRequest{
		Topic: testTopic,
		Key:   "sub-key",
		Index: 1,
	}

	nextEvent := Event{
		Topic:   testTopic,
		Index:   3,
		Payload: simplePayload{key: "sub-key", value: "event-3"},
	}

	handlers := SnapshotHandlers{
		testTopic: func(req SubscribeRequest, buf SnapshotAppender) (uint64, error) {
			if req.Topic != testTopic {
				return 0, fmt.Errorf("unexpected topic: %v", req.Topic)
			}
			buf.Append([]Event{testSnapshotEvent})
			buf.Append([]Event{nextEvent})
			return 3, nil
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	publisher := NewEventPublisher(handlers, time.Second)
	go publisher.Run(ctx)
	// Include the same events in the topicBuffer
	publisher.publishEvent([]Event{testSnapshotEvent})
	publisher.publishEvent([]Event{nextEvent})

	runStep(t, "start a subscription and unsub", func(t *testing.T) {
		sub, err := publisher.Subscribe(req)
		require.NoError(t, err)
		defer sub.Unsubscribe()

		eventCh := runSubscription(ctx, sub)
		next := getNextEvent(t, eventCh)
		require.True(t, next.IsNewSnapshotToFollow(),
			"expected newSnapshotToFollow, got: %v", next)

		next = getNextEvent(t, eventCh)
		require.Equal(t, testSnapshotEvent, next)

		next = getNextEvent(t, eventCh)
		require.Equal(t, nextEvent, next)

		next = getNextEvent(t, eventCh)
		require.True(t, next.IsEndOfSnapshot(),
			"expected endOfSnapshot, got: %v", next)
		require.Equal(t, uint64(3), next.Index)
	})

	publisher.snapshotHandlers[testTopic] = func(_ SubscribeRequest, _ SnapshotAppender) (uint64, error) {
		return 0, fmt.Errorf("error should not be seen, cache should have been used")
	}

	runStep(t, "resume the subscription", func(t *testing.T) {
		newReq := *req
		newReq.Index = 0
		sub, err := publisher.Subscribe(&newReq)
		require.NoError(t, err)

		eventCh := runSubscription(ctx, sub)
		next := getNextEvent(t, eventCh)
		require.Equal(t, testSnapshotEvent, next,
			"fresh subscriber (Index=0) should get snapshot data first, not a framing event")

		next = getNextEvent(t, eventCh)
		require.Equal(t, nextEvent, next)

		next = getNextEvent(t, eventCh)
		require.True(t, next.IsEndOfSnapshot())
	})
}
TESTEOF
fi

# Run the test
echo "Running test $TEST_NAME..."
OUTPUT=$(go test -v -run "^${TEST_NAME}$" -count=1 -timeout 60s ./agent/consul/stream/ 2>&1) || true

echo "$OUTPUT" | tail -30

echo ""
if echo "$OUTPUT" | grep -q "^--- PASS:"; then
    echo "PASS: Bug is fixed — $TEST_NAME passed"
    exit 0
else
    echo "FAIL: Bug is present — $TEST_NAME failed"
    exit 1
fi
