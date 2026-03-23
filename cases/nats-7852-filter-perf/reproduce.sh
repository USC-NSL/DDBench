#!/usr/bin/env bash
# Reproduction and verification script for nats-7852-filter-perf
# Extracts the test from the fix commit, runs it on the buggy version, and reports PASS/FAIL.
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7852-filter-perf"
FIX_COMMIT="66e9bbc7f8684dd1b31c54ef686924e0841f9846"
TEST_FILE="server/jetstream_consumer_test.go"
TEST_NAME="TestJetStreamConsumerSingleFilterSubjectInFilterSubjects"

export PATH=$PATH:/usr/local/go/bin

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

# Extract the test function from the fix commit and append it
echo "Extracting test $TEST_NAME from fix commit $FIX_COMMIT..."
git show "${FIX_COMMIT}:${TEST_FILE}" | sed -n "/^func ${TEST_NAME}(/,/^func /{ /^func ${TEST_NAME}(/p; /^func ${TEST_NAME}(/!{ /^func /!p; } }" >> "$TEST_FILE"

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
