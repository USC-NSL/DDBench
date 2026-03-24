#!/usr/bin/env bash
# Reproduction and verification script for nats-7726-mixed-filter
# Extracts the test from the fix commit, runs it on the buggy version, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7726-mixed-filter"
FIX_COMMIT="6aded805ec9625b20ee50ded3b63135d5fe3d0a8"
TEST_FILE="server/gsl/gsl_test.go"
TEST_NAME="TestGenericSublistInterestBasedIntersection"

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -f "$WORK_DIR/nats-server" ]; then
    echo "ERROR: Binary not found at $WORK_DIR/nats-server. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing nats-7726-mixed-filter ==="

cleanup() {
    [ -f "${TEST_FILE}.bak" ] && mv "${TEST_FILE}.bak" "$TEST_FILE"
}
trap cleanup EXIT

# Back up the original test file
cp "$TEST_FILE" "${TEST_FILE}.bak"

# The fix commit adds a "PWCDoesntHideLiteral" subtest to the existing test function.
# Instead of appending the whole function (which would duplicate), we add a standalone test.
echo "Adding PWCDoesntHideLiteral test..."
cat >> "$TEST_FILE" << 'TESTEOF'

func TestPWCDoesntHideLiteral(t *testing.T) {
	sl := NewSublistWithCache()
	sub1 := newSub("one.*.six")
	sl.Insert(sub1)
	sub2 := newSub("one.two.seven")
	sl.Insert(sub2)

	// Build stree from subjects
	stree := NewSubjectTree[int]()
	stree.Insert([]byte("one.two.six"), 1)
	stree.Insert([]byte("one.two.seven"), 2)

	r := sl.Intersect(stree)
	if len(r) != 2 {
		t.Fatalf("Expected 2 results, got %d (PWC hides literal)", len(r))
	}
}
TESTEOF

# Run the standalone test
echo "Running test TestPWCDoesntHideLiteral..."
TEST_OUTPUT=$(go test -v -run "TestPWCDoesntHideLiteral" -count=1 -timeout 120s ./server/gsl/ 2>&1) || true
TEST_EXIT=$?

echo "$TEST_OUTPUT" | tail -20

# Restore original file
mv "${TEST_FILE}.bak" "$TEST_FILE"

echo ""
if echo "$TEST_OUTPUT" | grep -q "^--- PASS: TestPWCDoesntHideLiteral"; then
    echo "PASS: Bug is fixed — PWC does not hide literal match"
    exit 0
else
    echo "FAIL: Bug is present — PWC hides literal match (expected 2 results, got fewer)"
    exit 1
fi
