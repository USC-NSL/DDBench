#!/usr/bin/env bash
# Reproduction and verification script for nats-7726-mixed-filter
# Extracts the test from the fix commit, runs it on the buggy version, and reports PASS/FAIL.
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7726-mixed-filter"
FIX_COMMIT="6aded805ec9625b20ee50ded3b63135d5fe3d0a8"
TEST_FILE="server/sublist_test.go"
TEST_NAME="TestGenericSublistInterestBasedIntersection"

export PATH=$PATH:/usr/local/go/bin

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

# Extract the test function from the fix commit and append it
echo "Extracting test $TEST_NAME from fix commit $FIX_COMMIT..."
git show "${FIX_COMMIT}:${TEST_FILE}" | sed -n "/^func ${TEST_NAME}(/,/^func /{ /^func ${TEST_NAME}(/p; /^func ${TEST_NAME}(/!{ /^func /!p; } }" >> "$TEST_FILE"

# Run the specific subtest
echo "Running test ${TEST_NAME}/PWCDoesntHideLiteral..."
TEST_OUTPUT=$(go test -v -run "${TEST_NAME}/PWCDoesntHideLiteral" -count=1 -timeout 120s ./server/ 2>&1) || true
TEST_EXIT=$?

echo "$TEST_OUTPUT" | tail -20

# Restore original file
mv "${TEST_FILE}.bak" "$TEST_FILE"

echo ""
if echo "$TEST_OUTPUT" | grep -q "^--- PASS:"; then
    echo "PASS: Bug is fixed — ${TEST_NAME}/PWCDoesntHideLiteral passed"
    exit 0
else
    echo "FAIL: Bug is present — ${TEST_NAME}/PWCDoesntHideLiteral failed"
    exit 1
fi
