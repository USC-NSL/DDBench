#!/usr/bin/env bash
# Reproduction and verification script for zookeeper-4846-fuzzy-snapshot-acl
# Injects a DataTree test: replaying a create for a node whose ACL was purged
# from the ACL cache during a fuzzy snapshot must leave a usable node.
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

# ── JUnit XML verdicts ──
# Decided from the JUnit XML report for the exact oracle test case: it must
# exist and contain no <failure>, <error> or <skipped>. Never from console text.
junit_result() {  # <xml-file> <test-method> -> pass | fail | skip | norun
    [ -f "$1" ] || { echo norun; return; }
    awk -v m="$2" '
        /<testcase[ >]/ {
            inc = ($0 ~ ("name=\"" m "([({[][^\"]*)?\""))
            if (inc) { found = 1
                if ($0 ~ /<(failure|error)[ >\/]/) bad = 1
                if ($0 ~ /<skipped/) skip = 1
                if ($0 ~ /\/>[[:space:]]*$/ || $0 ~ /<\/testcase>/) inc = 0 }
            next }
        inc && /<(failure|error)[ >\/]/ { bad = 1 }
        inc && /<skipped/ { skip = 1 }
        inc && /<\/testcase>/ { inc = 0 }
        END { if (!found) print "norun"; else if (bad) print "fail"; else if (skip) print "skip"; else print "pass" }
    ' "$1"
}
# Exit with the verdict for the oracle test case.
junit_verdict() {  # <xml> <method> <console-log> <pass-message> <fail-message>
    case "$(junit_result "$1" "$2")" in
        pass) pass "$4" ;;
        fail) fail "$5" ;;
        skip) fail "the oracle test was skipped" ;;
        *)
            if grep -qE "COMPILATION ERROR|Compilation failure|compilation failed|Compilation failed|error: |cannot find symbol" "$3"; then
                fail "the oracle test did not run: the worktree or the injected oracle test does not compile"
            fi
            error "the oracle test did not run and no compilation error was found (see output above)" ;;
    esac
}

TEST_CLASS=DDBenchOracleFuzzySnapshotAclTest
TEST_FILE="$WORK_DIR/zookeeper-server/src/test/java/org/apache/zookeeper/server/$TEST_CLASS.java"
TEST_METHOD=testCreateNodeRecoversPurgedACL
REPORT="$WORK_DIR/zookeeper-server/target/surefire-reports/TEST-org.apache.zookeeper.server.$TEST_CLASS.xml"
LOG="$RUN_DIR/mvn-test.log"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

rebuild_worktree
[ -d "$WORK_DIR/zookeeper-server" ] || error "zookeeper-server not found in $WORK_DIR (run setup first)"

echo "=== Reproducing zookeeper-4846-fuzzy-snapshot-acl ==="

cleanup() {
    rm -f "$TEST_FILE"
    # Reports and classes compiled from the injected test must not outlive the run.
    rm -rf "$WORK_DIR/zookeeper-server/target/surefire-reports"
    find "$WORK_DIR/zookeeper-server/target/test-classes" -name 'DDBenchOracle*.class' -delete 2>/dev/null
}
trap cleanup EXIT

cat > "$TEST_FILE" << 'JAVAEOF'
package org.apache.zookeeper.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.fail;
import java.util.List;
import org.apache.zookeeper.KeeperException;
import org.apache.zookeeper.ZooDefs;
import org.apache.zookeeper.data.ACL;
import org.junit.jupiter.api.Test;

/**
 * Regression test for ZOOKEEPER-4846.
 * Simulates the fuzzy snapshot ACL race:
 * 1. A node exists in the DataTree with an ACL reference
 * 2. The ACL is purged from the cache during fuzzy snapshot serialization
 * 3. fastForwardFromEdits replays a createNode for the same path
 *
 * Buggy code: throws NodeExistsException without restoring the ACL,
 *   leaving the node with a stale ACL reference. Subsequent operations
 *   on the node crash with "Failed to fetch acls for X".
 * Fixed code: sets the ACL on the existing node before throwing
 *   NodeExistsException, so the node has a valid ACL reference.
 */
public class DDBenchOracleFuzzySnapshotAclTest {

    @Test
    public void testCreateNodeRecoversPurgedACL() throws Exception {
        DataTree dt = new DataTree();
        ReferenceCountedACLCache aclCache = dt.getReferenceCountedAclCache();

        // Create a node with a specific ACL (not OPEN_ACL_UNSAFE)
        List<ACL> nodeAcl = ZooDefs.Ids.CREATOR_ALL_ACL;
        dt.createNode("/testnode", new byte[0], nodeAcl, -1, 1, 1, 0);

        // Verify node was created with a non-default ACL
        Long aclId = dt.getNode("/testnode").acl;
        // aclId should be > 0 (not OPEN_ACL_UNSAFE which is 0)

        // Simulate fuzzy snapshot: purge the ACL from the cache
        aclCache.removeUsage(aclId);
        // Force purge of unused entries
        aclCache.purgeUnused();

        // Now simulate fastForwardFromEdits: call createNode for the same path.
        // On buggy code: the existing node has a stale ACL reference.
        //   The code checks parent.getChildren().contains(childName) → true,
        //   throws NodeExistsException WITHOUT restoring the ACL.
        //   The node still has the stale ACL reference.
        // On fixed code: the code checks nodes.get(path) != null → true,
        //   sets existingChild.acl = acls (restoring the ACL), THEN throws
        //   NodeExistsException. The node now has a valid ACL reference.
        try {
            dt.createNode("/testnode", new byte[0], nodeAcl, -1, 1, 1, 0);
            fail("Should have thrown NodeExistsException");
        } catch (KeeperException.NodeExistsException e) {
            // Expected
        }

        // KEY ASSERTION: After the createNode call for the existing path,
        // the node should have a valid ACL reference.
        // On buggy code: the ACL reference is still stale, so any operation
        //   that looks up the ACL (like getACL) will fail with RuntimeException.
        // On fixed code: the ACL was restored, so getACL works.
        try {
            List<ACL> retrievedAcl = dt.getACL(dt.getNode("/testnode"));
            // Verify the ACL was correctly restored
            assertEquals(nodeAcl, retrievedAcl,
                "ACL should be correctly restored after createNode on existing path");
        } catch (RuntimeException e) {
            fail("Bug present: RuntimeException when creating child under node with purged ACL: " + e.getMessage());
        }
    }
}
JAVAEOF

cd "$WORK_DIR/zookeeper-server"
rm -rf target/surefire-reports
echo "Running $TEST_CLASS#$TEST_METHOD ..."
mvn test -Dtest="$TEST_CLASS#$TEST_METHOD" -DfailIfNoTests=false -q > "$LOG" 2>&1
tail -40 "$LOG"
junit_verdict "$REPORT" "$TEST_METHOD" "$LOG" \
    "Bug is fixed — nodes replayed with a purged ACL reference remain usable" \
    "Bug is present — a node replayed with a purged ACL reference breaks later operations"
