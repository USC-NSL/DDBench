#!/usr/bin/env bash
# Reproduction and verification script for zookeeper-4846-fuzzy-snapshot-acl
# Injects a regression test that simulates the fuzzy snapshot ACL race:
# A node exists with a purged ACL. When createNode is called for the same path
# (simulating fastForwardFromEdits replay), the buggy code throws
# NodeExistsException without restoring the ACL. The fix sets the ACL on the
# existing node before throwing.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/zookeeper-4846-fuzzy-snapshot-acl"
INJECT_TEST="$WORK_DIR/zookeeper-server/src/test/java/org/apache/zookeeper/server/Zk4846Test.java"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing zookeeper-4846-fuzzy-snapshot-acl ==="

cleanup() {
    rm -f "$INJECT_TEST"
}
trap cleanup EXIT

# Inject a standalone regression test
cat > "$INJECT_TEST" << 'JAVAEOF'
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
public class Zk4846Test {

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

echo "Injected regression test: $INJECT_TEST"
echo "Running Maven test..."

cd "$WORK_DIR/zookeeper-server"
OUTPUT=$(mvn test -Dmaven.repo.local=/workspace/.m2 -Dtest="Zk4846Test#testCreateNodeRecoversPurgedACL" -DfailIfNoTests=false -q 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present -- createNode does not defensively recover missing ACL reference, causing RuntimeException when accessing a node whose ACL was purged during fuzzy snapshot"
    exit 1
else
    echo "PASS: Bug is fixed -- createNode defensively recovers missing ACL reference during fastForwardFromEdits"
    exit 0
fi
