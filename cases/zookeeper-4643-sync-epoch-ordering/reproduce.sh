#!/usr/bin/env bash
# Reproduction and verification script for zookeeper-4643-sync-epoch-ordering
# Injects a standalone regression test that verifies the ordering of epoch
# updates vs transaction persistence during ZAB synchronization.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/zookeeper-4643-sync-epoch-ordering"
TEST_DIR="$WORK_DIR/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum"
INJECT_TEST="$TEST_DIR/Zk4643RegressionTest.java"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing zookeeper-4643-sync-epoch-ordering ==="

cleanup() {
    rm -f "$INJECT_TEST"
}
trap cleanup EXIT

# Inject a standalone regression test.
# This test extends Zab1_0Test to reuse its testFollowerConversation framework.
# It verifies that during NEWLEADER processing, only committed transactions are
# persisted to disk, and the epoch is updated after persistence.
cat > "$INJECT_TEST" << 'JAVAEOF'
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
public class Zk4643RegressionTest extends Zab1_0Test {

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

                    // Verify data is now updated
                    TrackerWatcher watcher = new TrackerWatcher();
                    assertEquals("data1", new String(f.fzk.getZKDatabase().getData("/foo", stat, watcher)));
                    watcher.waitForChange();
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

echo "Injected regression test: $INJECT_TEST"
echo "Running Maven test..."

cd "$WORK_DIR/zookeeper-server"
OUTPUT=$(mvn test -Dmaven.repo.local=/workspace/.m2 -Dtest="Zk4643RegressionTest#testOnlyCommittedTxnsPersistedBeforeEpochUpdate" -DfailIfNoTests=false -q 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present — follower persists uncommitted proposals before updating epoch during NEWLEADER processing"
    exit 1
else
    echo "PASS: Bug is fixed — only committed transactions are persisted before epoch update"
    exit 0
fi
