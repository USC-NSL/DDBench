#!/usr/bin/env bash
# Reproduction and verification script for nats-7308-delete-nonexistent-reset
# Injects a cluster test from the fix PR into the buggy codebase, runs it, and reports PASS/FAIL.
# The test creates an R3 stream, publishes one message, then deletes a non-existent sequence (past EOF).
# On the buggy version, this triggers a cluster state reset and the client times out.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7308-delete-nonexistent-reset"
TEST_FILE="server/jetstream_cluster_1_test.go"
TEST_NAME="TestJetStreamClusterDeleteMsgEOF"

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -f "$WORK_DIR/nats-server" ]; then
    echo "ERROR: Binary not found at $WORK_DIR/nats-server. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing nats-7308-delete-nonexistent-reset ==="

cleanup() {
    [ -f "${TEST_FILE}.bak" ] && mv "${TEST_FILE}.bak" "$TEST_FILE"
}
trap cleanup EXIT

# Back up the original test file and inject the test only if not already present
cp "$TEST_FILE" "${TEST_FILE}.bak"

NEED_INJECT=true
if grep -q "$TEST_NAME" "$TEST_FILE"; then
    NEED_INJECT=false
fi

if $NEED_INJECT; then
# Append the test function from the fix PR (adapted for v2.11.8 API)
cat >> "$TEST_FILE" << 'TESTEOF'

func TestJetStreamClusterDeleteMsgEOF(t *testing.T) {
	for _, replicas := range []int{1, 3} {
		t.Run(fmt.Sprintf("R%d", replicas), func(t *testing.T) {
			c := createJetStreamClusterExplicit(t, "R3S", 3)
			defer c.shutdown()

			nc, js := jsClientConnect(t, c.randomServer())
			defer nc.Close()

			_, err := js.AddStream(&nats.StreamConfig{
				Name:     "TEST",
				Subjects: []string{"foo"},
				Replicas: replicas,
			})
			require_NoError(t, err)

			_, err = js.Publish("foo", nil)
			require_NoError(t, err)

			require_Error(t, js.DeleteMsg("TEST", 0), NewJSNoMessageFoundError())
			require_NoError(t, js.DeleteMsg("TEST", 1))
			require_Error(t, js.DeleteMsg("TEST", 1), NewJSNoMessageFoundError())
			require_Error(t, js.DeleteMsg("TEST", 2), NewJSStreamMsgDeleteFailedError(ErrStoreEOF))
		})
	}
}
TESTEOF
fi

# Run the test (both R1 and R3 subtests)
echo "Running test $TEST_NAME..."
TEST_OUTPUT=$(go test -v -run "$TEST_NAME" -count=1 -timeout 120s ./server/ 2>&1) || true
echo "$TEST_OUTPUT" | tail -30

# Restore original file
mv "${TEST_FILE}.bak" "$TEST_FILE"
trap - EXIT

echo ""

# Check results
if echo "$TEST_OUTPUT" | grep -q "^--- PASS: $TEST_NAME"; then
    echo "PASS: Bug is fixed — deleting non-existent sequence returns error without cluster reset"
    exit 0
else
    echo "FAIL: Bug is present —"
    if echo "$TEST_OUTPUT" | grep -q "FAIL.*R3"; then
        echo "  - R3 subtest failed (cluster state reset triggered by ErrStoreEOF on delete)"
    fi
    if echo "$TEST_OUTPUT" | grep -q "FAIL.*R1"; then
        echo "  - R1 subtest failed"
    fi
    exit 1
fi
