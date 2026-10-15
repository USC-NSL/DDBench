#!/usr/bin/env bash
# Reproduction and verification script for zookeeper-4643-sync-epoch-ordering
# Injects a test (extending Zab1_0Test's follower conversation framework) that
# checks that, while a follower processes NEWLEADER, only committed transactions
# are persisted before its epoch is updated.
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

TEST_CLASS=DDBenchOracleSyncEpochTest
TEST_FILE="$WORK_DIR/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/$TEST_CLASS.java"
TEST_METHOD=testOnlyCommittedTxnsPersistedBeforeEpochUpdate
REPORT="$WORK_DIR/zookeeper-server/target/surefire-reports/TEST-org.apache.zookeeper.server.quorum.$TEST_CLASS.xml"
LOG="$RUN_DIR/mvn-test.log"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

rebuild_worktree
[ -d "$WORK_DIR/zookeeper-server" ] || error "zookeeper-server not found in $WORK_DIR (run setup first)"

echo "=== Reproducing zookeeper-4643-sync-epoch-ordering ==="

cleanup() {
    rm -f "$TEST_FILE"
    # Reports and classes compiled from the injected test must not outlive the run.
    rm -rf "$WORK_DIR/zookeeper-server/target/surefire-reports"
    find "$WORK_DIR/zookeeper-server/target/test-classes" -name 'DDBenchOracle*.class' -delete 2>/dev/null
}
trap cleanup EXIT

cat > "$TEST_FILE" << 'JAVAEOF'
package org.apache.zookeeper.server.quorum;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.verify;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import org.apache.jute.BinaryOutputArchive;
import org.apache.jute.InputArchive;
import org.apache.jute.OutputArchive;
import org.apache.zookeeper.ZooDefs;
import org.apache.zookeeper.data.Stat;
import org.apache.zookeeper.server.ZKDatabase;
import org.apache.zookeeper.server.persistence.FileTxnSnapLog;
import org.apache.zookeeper.server.util.ZxidUtils;
import org.apache.zookeeper.test.TestUtils;
import org.apache.zookeeper.txn.CreateTxn;
import org.apache.zookeeper.txn.SetDataTxn;
import org.apache.zookeeper.txn.TxnHeader;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Regression test for ZOOKEEPER-4643.
 * Verifies that when a follower processes NEWLEADER during ZAB sync,
 * only committed transactions are persisted before the epoch is updated.
 *
 * On buggy code, ALL proposals (including uncommitted) are persisted,
 * which means a follower that crashes after epoch update can later become
 * leader with stale history, issuing improper TRUNC commands.
 */
public class DDBenchOracleSyncEpochTest extends Zab1_0Test {

    @Test
    public void testOnlyCommittedTxnsPersistedBeforeEpochUpdate(@TempDir File testData) throws Exception {
        testFollowerConversation(new FollowerConversation() {
            @Override
            public void converseWithFollower(InputArchive ia, OutputArchive oa, Follower f) throws Exception {
                File tmpDir = File.createTempFile("test", "dir", testData);
                tmpDir.delete();
                tmpDir.mkdir();
                File logDir = f.fzk.getTxnLogFactory().getDataLogDir().getParentFile();
                File snapDir = f.fzk.getTxnLogFactory().getSnapDir().getParentFile();
                f.zk = spy(f.zk);
                try {
                    assertEquals(0, f.self.getAcceptedEpoch());
                    assertEquals(0, f.self.getCurrentEpoch());

                    // Setup a database with a single /foo node
                    ZKDatabase zkDb = new ZKDatabase(new FileTxnSnapLog(tmpDir, tmpDir));
                    final long firstZxid = ZxidUtils.makeZxid(1, 1);
                    zkDb.processTxn(new TxnHeader(13, 1313, firstZxid, 33, ZooDefs.OpCode.create),
                        new CreateTxn("/foo", "data1".getBytes(), ZooDefs.Ids.OPEN_ACL_UNSAFE, false, 1), null);
                    Stat stat = new Stat();
                    assertEquals("data1", new String(zkDb.getData("/foo", stat, null)));

                    // FOLLOWERINFO handshake
                    QuorumPacket qp = new QuorumPacket();
                    readPacketSkippingPing(ia, qp);
                    assertEquals(Leader.FOLLOWERINFO, qp.getType());
                    assertEquals(qp.getZxid(), 0);

                    // LEADERINFO
                    qp.setType(Leader.LEADERINFO);
                    qp.setZxid(ZxidUtils.makeZxid(1, 0));
                    byte[] protoBytes = new byte[4];
                    ByteBuffer.wrap(protoBytes).putInt(0x10000);
                    qp.setData(protoBytes);
                    oa.writeRecord(qp, null);

                    // ACKEPOCH
                    readPacketSkippingPing(ia, qp);
                    assertEquals(Leader.ACKEPOCH, qp.getType());
                    assertEquals(1, f.self.getAcceptedEpoch());
                    assertEquals(0, f.self.getCurrentEpoch());

                    // Send SNAP with the database
                    qp.setType(Leader.SNAP);
                    qp.setData(new byte[0]);
                    qp.setZxid(zkDb.getDataTreeLastProcessedZxid());
                    oa.writeRecord(qp, null);
                    zkDb.serializeSnapshot(oa);
                    oa.writeString("BenWasHere", null);
                    Thread.sleep(10);
                    verify(f.zk, never()).takeSnapshot();

                    // Send an outstanding (UNCOMMITTED) proposal
                    long proposalZxid = ZxidUtils.makeZxid(1, 1001);
                    proposeSetData(qp, proposalZxid, "data2", 2);
                    oa.writeRecord(qp, null);

                    // Send NEWLEADER (no COMMIT for proposalZxid yet)
                    qp.setType(Leader.NEWLEADER);
                    qp.setZxid(ZxidUtils.makeZxid(1, 0));
                    qp.setData(null);
                    oa.writeRecord(qp, null);

                    // Read NEWLEADER ACK
                    readPacketSkippingPing(ia, qp);
                    assertEquals(Leader.ACK, qp.getType());
                    assertEquals(ZxidUtils.makeZxid(1, 0), qp.getZxid());
                    assertEquals(1, f.self.getAcceptedEpoch());
                    assertEquals(1, f.self.getCurrentEpoch());

                    // KEY ASSERTION: verify snapshot was taken during NEWLEADER processing
                    verify(f.zk).takeSnapshot(true);
                    // KEY ASSERTION: only committed zxid should be lastProcessed
                    assertEquals(firstZxid, f.fzk.getLastProcessedZxid());

                    // KEY ASSERTION: on disk, only committed data should exist
                    // On buggy code, the uncommitted proposal is persisted, so lastZxid == proposalZxid
                    ZKDatabase zkDb2 = new ZKDatabase(new FileTxnSnapLog(logDir, snapDir));
                    long lastZxid = zkDb2.loadDataBase();
                    assertEquals("data1", new String(zkDb2.getData("/foo", stat, null)));
                    assertEquals(firstZxid, lastZxid);

                    // Now send COMMIT + UPTODATE to let the follower proceed
                    qp.setType(Leader.COMMIT);
                    qp.setZxid(proposalZxid);
                    qp.setData(null);
                    oa.writeRecord(qp, null);

                    qp.setType(Leader.UPTODATE);
                    qp.setZxid(0);
                    qp.setData(null);
                    oa.writeRecord(qp, null);

                    // Read UPTODATE ACK
                    readPacketSkippingPing(ia, qp);
                    assertEquals(Leader.ACK, qp.getType());
                    assertEquals(ZxidUtils.makeZxid(1, 0), qp.getZxid());

                    // Read PROPOSAL ACK
                    readPacketSkippingPing(ia, qp);
                    assertEquals(Leader.ACK, qp.getType());
                    assertEquals(proposalZxid, qp.getZxid());

                    // Verify the committed proposal is applied (poll: whether it is
                    // already applied at this point depends on scheduling).
                    long deadline = System.currentTimeMillis() + 10000;
                    while (!"data2".equals(new String(f.fzk.getZKDatabase().getData("/foo", stat, null)))
                            && System.currentTimeMillis() < deadline) {
                        Thread.sleep(50);
                    }
                    assertEquals("data2", new String(f.fzk.getZKDatabase().getData("/foo", stat, null)));

                    // Final verification: data persisted correctly
                    zkDb2 = new ZKDatabase(new FileTxnSnapLog(logDir, snapDir));
                    lastZxid = zkDb2.loadDataBase();
                    assertEquals("data2", new String(zkDb2.getData("/foo", stat, null)));
                    assertEquals(proposalZxid, lastZxid);
                } finally {
                    TestUtils.deleteFileRecursively(tmpDir);
                }
            }

            private void proposeSetData(QuorumPacket qp, long zxid, String data, int version) throws IOException {
                qp.setType(Leader.PROPOSAL);
                qp.setZxid(zxid);
                TxnHeader hdr = new TxnHeader(4, 1414, qp.getZxid(), 55, ZooDefs.OpCode.setData);
                SetDataTxn sdt = new SetDataTxn("/foo", data.getBytes(), version);
                ByteArrayOutputStream baos = new ByteArrayOutputStream();
                OutputArchive boa = BinaryOutputArchive.getArchive(baos);
                boa.writeRecord(hdr, null);
                boa.writeRecord(sdt, null);
                qp.setData(baos.toByteArray());
            }
        }, testData);
    }
}
JAVAEOF

cd "$WORK_DIR/zookeeper-server"
rm -rf target/surefire-reports
echo "Running $TEST_CLASS#$TEST_METHOD ..."
mvn test -Dtest="$TEST_CLASS#$TEST_METHOD" -DfailIfNoTests=false -q > "$LOG" 2>&1
tail -40 "$LOG"
junit_verdict "$REPORT" "$TEST_METHOD" "$LOG" \
    "Bug is fixed — only committed transactions are persisted before the epoch update" \
    "Bug is present — the follower persisted uncommitted proposals before updating its epoch"
