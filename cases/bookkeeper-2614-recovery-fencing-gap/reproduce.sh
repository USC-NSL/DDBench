#!/usr/bin/env bash
# Reproduce script for bookkeeper-2614-recovery-fencing-gap
# Verifies that recovery reads carry the fencing flag, preventing the original
# writer from committing entries after ledger recovery has closed the ledger.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/bookkeeper-2614-recovery-fencing-gap"
FIX_COMMIT="017307bc67431a7616861ad09927c4e3327633d1"
RESULT_LOG="/tmp/bk_2614_test_output.txt"

echo "=== Reproducing bookkeeper-2614-recovery-fencing-gap ==="

cd "$WORK_DIR"

# Use a persistent Maven local repo inside the workspace volume so the
# SNAPSHOT artifacts from setup are reusable across containers.
M2_REPO="/workspace/.m2"
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh" 2>&1 | tail -5 || \
    mvn -pl bookkeeper-server -am clean install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -Dmaven.repo.local="$M2_REPO" -q

# Reset to buggy state (production code must be at buggy commit)
git checkout -- bookkeeper-server/src/main/java/org/apache/bookkeeper/client/PendingReadOp.java 2>/dev/null || true

# Inject test infrastructure from the fix commit.
# These are test-only files: MockBookies.java (new), MockLedgerData.java (new),
# updated MockBookieClient.java, updated MockClientContext.java, and
# LedgerRecovery2Test.java (new test added). The production code stays at the
# buggy commit so PendingReadOp still lacks FLAG_DO_FENCING in recovery reads.
git checkout "$FIX_COMMIT" -- \
    bookkeeper-server/src/test/java/org/apache/bookkeeper/proto/MockBookies.java \
    bookkeeper-server/src/test/java/org/apache/bookkeeper/proto/MockLedgerData.java \
    bookkeeper-server/src/test/java/org/apache/bookkeeper/proto/MockBookieClient.java \
    bookkeeper-server/src/test/java/org/apache/bookkeeper/client/MockClientContext.java \
    bookkeeper-server/src/test/java/org/apache/bookkeeper/client/LedgerRecovery2Test.java

echo "Test infrastructure injected. Production code remains at buggy commit."

# Run the specific test
echo "Running testFirstWriterCannotCommitWriteAfter2ndWriterCloses..."
set +e
mvn -pl bookkeeper-server test \
    -Dtest="LedgerRecovery2Test#testFirstWriterCannotCommitWriteAfter2ndWriterCloses" \
    -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip \
    -Dsurefire.failIfNoSpecifiedTests=false \
    -Dmaven.repo.local="$M2_REPO" \
    2>&1 | tee "$RESULT_LOG"
set -e

if grep -qE "BUILD SUCCESS" "$RESULT_LOG" && grep -qE "Tests run:.*Failures: 0.*Errors: 0" "$RESULT_LOG"; then
    echo ""
    echo "PASS: Bug is fixed"
    exit 0
else
    echo ""
    echo "FAIL: Bug is present — recovery reads do not carry fencing flag; original writer can commit after recovery close"
    exit 1
fi
