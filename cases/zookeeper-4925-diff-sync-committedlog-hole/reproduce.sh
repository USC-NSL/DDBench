#!/usr/bin/env bash
# Reproduction and verification script for zookeeper-4925-diff-sync-committedlog-hole
# Injects a 3-node ensemble test: a stale follower brought up to date by a DIFF
# sync and later elected leader must still serve all committed data.
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

TEST_CLASS=DDBenchOracleQuorumSyncTest
TEST_FILE="$WORK_DIR/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/$TEST_CLASS.java"
TEST_METHOD=testStaleDiffSync
REPORT="$WORK_DIR/zookeeper-server/target/surefire-reports/TEST-org.apache.zookeeper.server.quorum.$TEST_CLASS.xml"
LOG="$RUN_DIR/mvn-test.log"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

rebuild_worktree
[ -d "$WORK_DIR/zookeeper-server" ] || error "zookeeper-server not found in $WORK_DIR (run setup first)"

echo "=== Reproducing zookeeper-4925-diff-sync-committedlog-hole ==="

cleanup() {
    rm -f "$TEST_FILE"
    # Reports and classes compiled from the injected test must not outlive the run.
    rm -rf "$WORK_DIR/zookeeper-server/target/surefire-reports"
    find "$WORK_DIR/zookeeper-server/target/test-classes" -name 'DDBenchOracle*.class' -delete 2>/dev/null
}
trap cleanup EXIT

cat > "$TEST_FILE" << 'JAVAEOF'
package org.apache.zookeeper.server.quorum;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import java.util.Comparator;
import org.apache.zookeeper.CreateMode;
import org.apache.zookeeper.ZKTestCase;
import org.apache.zookeeper.ZooDefs;
import org.apache.zookeeper.ZooKeeper;
import org.apache.zookeeper.test.ClientBase;
import org.apache.zookeeper.test.QuorumUtil;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

public class DDBenchOracleQuorumSyncTest extends ZKTestCase {
    private QuorumUtil qu;

    @AfterEach
    public void tearDown() throws Exception {
        if (qu != null) {
            qu.shutdownAll();
        }
    }

    @Test
    public void testStaleDiffSync() throws Exception {
        qu = new QuorumUtil(2);
        qu.startAll();

        int[] followerIds = qu.getFollowerQuorumPeers()
            .stream()
            .sorted(Comparator.comparingLong(QuorumPeer::getMyId).reversed())
            .mapToInt(peer -> (int) peer.getMyId()).toArray();

        int follower1 = followerIds[0];
        int follower2 = followerIds[1];

        String leaderConnectString = qu.getConnectString(qu.getLeaderQuorumPeer());
        try (ZooKeeper zk = ClientBase.createZKClient(leaderConnectString)) {
            qu.shutdown(follower2);

            for (int i = 0; i < 10; i++) {
                zk.create("/foo" + i, null, ZooDefs.Ids.OPEN_ACL_UNSAFE, CreateMode.PERSISTENT);
            }

            qu.shutdown(follower1);

            for (int i = 0; i < 10; i++) {
                zk.create("/bar" + i, null, ZooDefs.Ids.OPEN_ACL_UNSAFE, CreateMode.PERSISTENT);
            }

            qu.restart(follower1);
        }

        try (ZooKeeper zk = ClientBase.createZKClient(qu.getConnectionStringForServer(follower1))) {
            for (int i = 0; i < 10; i++) {
                String path = "/foo" + i;
                assertNotNull(zk.exists(path, false), path + " not found");
            }

            for (int i = 0; i < 10; i++) {
                String path = "/bar" + i;
                assertNotNull(zk.exists(path, false), path + " not found");
            }
        }

        qu.shutdown(qu.getLeaderServer());

        qu.restart(follower2);

        try (ZooKeeper zk = ClientBase.createZKClient(qu.getConnectionStringForServer(follower2))) {
            for (int i = 0; i < 10; i++) {
                String path = "/foo" + i;
                assertNotNull(zk.exists(path, false), path + " not found");
            }

            for (int i = 0; i < 10; i++) {
                String path = "/bar" + i;
                assertNotNull(zk.exists(path, false), path + " not found");
            }
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
    "Bug is fixed — all committed data is present after the DIFF sync and failover" \
    "Bug is present — committed data is missing after the DIFF sync and failover"
