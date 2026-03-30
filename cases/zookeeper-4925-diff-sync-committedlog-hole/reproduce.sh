#!/usr/bin/env bash
# Reproduction and verification script for zookeeper-4925-diff-sync-committedlog-hole
# Injects an integration test that verifies committedLog consistency after DIFF sync.
# -- Docker mode (preferred) --
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# -- Host fallback (no Docker) --
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/zookeeper-4925-diff-sync-committedlog-hole"
TEST_DIR="$WORK_DIR/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum"
INJECT_TEST="$TEST_DIR/QuorumSyncTest.java"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

# -- Rebuild if source changed --
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing zookeeper-4925-diff-sync-committedlog-hole ==="

cleanup() {
    rm -f "$INJECT_TEST"
}
trap cleanup EXIT

# Inject an integration regression test.
# This test starts a 3-node ZK ensemble, creates data on the leader, shuts down
# followers at specific points, restarts them to trigger DIFF sync, and verifies
# data consistency. On buggy code, the committedLog has a hole after DIFF sync,
# so when the stale follower becomes leader, committed data is lost.
cat > "$INJECT_TEST" << 'JAVAEOF'
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

public class QuorumSyncTest extends ZKTestCase {
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

echo "Injected regression test: $INJECT_TEST"
echo "Running Maven test..."

cd "$WORK_DIR/zookeeper-server"
OUTPUT=$(mvn test -Dtest="QuorumSyncTest#testStaleDiffSync" -DfailIfNoTests=false -q 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present — committedLog hole after DIFF sync causes data loss when stale follower becomes leader"
    exit 1
else
    echo "PASS: Bug is fixed — all committed data is present after leader failover and DIFF sync"
    exit 0
fi
