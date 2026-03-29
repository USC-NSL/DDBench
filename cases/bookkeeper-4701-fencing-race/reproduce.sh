#!/usr/bin/env bash
# Reproduction and verification script for bookkeeper-4701-fencing-race
# Injects a race-condition test into bookkeeper-server, runs it, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/bookkeeper-4701-fencing-race"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR/bookkeeper-server" ]; then
    echo "ERROR: Project not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

cd "$WORK_DIR"

echo "=== Reproducing bookkeeper-4701-fencing-race ==="

# ── Inject the race-condition test ──
TEST_DIR="bookkeeper-server/src/test/java/org/apache/bookkeeper/bookie"
mkdir -p "$TEST_DIR"

cat > "$TEST_DIR/HandleFactoryRaceTest.java" << 'TESTEOF'
/*
 * Test for BookKeeper PR #4701: Race condition in HandleFactoryImpl.getHandle().
 *
 * Bug: getHandle() calls putIfAbsent() but ignores the return value.
 * When two threads call getHandle() simultaneously for a ledger not yet in the
 * map, each creates a separate LedgerDescriptor. Since addEntry() and
 * fenceAndLogInJournal() synchronize on the LedgerDescriptor instance, using
 * different instances means the fence can be bypassed, causing entry loss.
 *
 * This test verifies that concurrent getHandle() calls for the same ledger
 * always return the same LedgerDescriptor instance.
 */
package org.apache.bookkeeper.bookie;

import static org.junit.Assert.fail;

import io.netty.buffer.UnpooledByteBufAllocator;
import java.io.File;
import java.lang.reflect.Field;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import org.apache.bookkeeper.bookie.storage.ldb.DbLedgerStorage;
import org.apache.bookkeeper.conf.ServerConfiguration;
import org.apache.bookkeeper.conf.TestBKConfiguration;
import org.apache.bookkeeper.stats.NullStatsLogger;
import org.apache.bookkeeper.util.DiskChecker;
import org.apache.bookkeeper.util.collections.ConcurrentLongHashMap;
import org.junit.After;
import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

public class HandleFactoryRaceTest {

    @Rule
    public TemporaryFolder tempDir = new TemporaryFolder();

    private LedgerStorage ledgerStorage;
    private HandleFactoryImpl handleFactory;

    @Before
    public void setUp() throws Exception {
        File ledgerDir = tempDir.newFolder("ledgers");
        File journalDir = tempDir.newFolder("journal");
        File indexDir = tempDir.newFolder("index");

        ServerConfiguration conf = TestBKConfiguration.newServerConfiguration();
        conf.setLedgerDirNames(new String[]{ledgerDir.getAbsolutePath()});
        conf.setJournalDirName(journalDir.getAbsolutePath());
        conf.setIndexDirName(new String[]{indexDir.getAbsolutePath()});
        conf.setLedgerStorageClass(DbLedgerStorage.class.getName());
        conf.setProperty("dbStorage_writeCacheMaxSizeMb", 1);
        conf.setProperty("dbStorage_readAheadCacheMaxSizeMb", 1);

        ledgerStorage = new DbLedgerStorage();
        LedgerDirsManager ledgerDirsManager = new LedgerDirsManager(
                conf, conf.getLedgerDirs(),
                new DiskChecker(conf.getDiskUsageThreshold(), conf.getDiskUsageWarnThreshold()));
        LedgerDirsManager indexDirsManager = new LedgerDirsManager(
                conf, conf.getIndexDirs(),
                new DiskChecker(conf.getDiskUsageThreshold(), conf.getDiskUsageWarnThreshold()));
        ledgerStorage.initialize(conf, null, ledgerDirsManager, indexDirsManager,
                NullStatsLogger.INSTANCE, UnpooledByteBufAllocator.DEFAULT);

        handleFactory = new HandleFactoryImpl(ledgerStorage);
    }

    @After
    public void tearDown() throws Exception {
        if (ledgerStorage != null) {
            ledgerStorage.shutdown();
        }
    }

    /**
     * Clear the internal ledger map so that the next getHandle() call goes through
     * the create-and-putIfAbsent path. Uses reflection since the field is private.
     */
    @SuppressWarnings("unchecked")
    private void clearLedgerMap() throws Exception {
        Field field = HandleFactoryImpl.class.getDeclaredField("ledgers");
        field.setAccessible(true);
        ConcurrentLongHashMap<LedgerDescriptor> map =
                (ConcurrentLongHashMap<LedgerDescriptor>) field.get(handleFactory);
        map.clear();
    }

    @Test
    public void testConcurrentGetHandleReturnsSameInstance() throws Exception {
        final byte[] masterKey = "testkey".getBytes();
        final int NUM_TRIALS = 500;
        final AtomicInteger raceCount = new AtomicInteger(0);

        for (int trial = 0; trial < NUM_TRIALS; trial++) {
            // Use a unique ledger ID each trial to avoid reusing cached handles
            final long ledgerId = 1000 + trial;

            // Clear the map to force the create-and-putIfAbsent code path
            clearLedgerMap();

            final CyclicBarrier barrier = new CyclicBarrier(2);
            final AtomicReference<LedgerDescriptor> handle1 = new AtomicReference<>();
            final AtomicReference<LedgerDescriptor> handle2 = new AtomicReference<>();
            final AtomicReference<Throwable> error1 = new AtomicReference<>();
            final AtomicReference<Throwable> error2 = new AtomicReference<>();

            Thread t1 = new Thread(() -> {
                try {
                    barrier.await();
                    handle1.set(handleFactory.getHandle(ledgerId, masterKey, false));
                } catch (Throwable t) {
                    error1.set(t);
                }
            });

            Thread t2 = new Thread(() -> {
                try {
                    barrier.await();
                    handle2.set(handleFactory.getHandle(ledgerId, masterKey, false));
                } catch (Throwable t) {
                    error2.set(t);
                }
            });

            t1.start();
            t2.start();
            t1.join(5000);
            t2.join(5000);

            if (error1.get() != null || error2.get() != null) {
                // Errors might happen for various reasons; skip this trial
                continue;
            }

            LedgerDescriptor h1 = handle1.get();
            LedgerDescriptor h2 = handle2.get();

            if (h1 != null && h2 != null && h1 != h2) {
                raceCount.incrementAndGet();
            }
        }

        if (raceCount.get() > 0) {
            System.out.println("");
            System.out.println("FAIL: Bug is present -- concurrent getHandle() returned different "
                    + "LedgerDescriptor instances in " + raceCount.get() + "/" + NUM_TRIALS
                    + " trials. Fencing can be bypassed.");
            fail("Race condition detected: getHandle() returned different LedgerDescriptor "
                    + "instances " + raceCount.get() + " times out of " + NUM_TRIALS + " trials");
        } else {
            System.out.println("");
            System.out.println("PASS: Bug is fixed -- all " + NUM_TRIALS
                    + " concurrent getHandle() trials returned the same LedgerDescriptor instance");
        }
    }
}
TESTEOF

echo "Test injected at: $TEST_DIR/HandleFactoryRaceTest.java"
echo ""

# ── Run the test ──
echo "Running HandleFactoryRaceTest (this may take 1-2 minutes)..."
echo ""

MVN_OUTPUT=$(mvn -pl bookkeeper-server test \
    -Dtest=HandleFactoryRaceTest \
    -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip \
    -Dsurefire.useFile=false \
    2>&1) || true

# Extract result from output
echo "$MVN_OUTPUT" | tail -30

# Determine PASS/FAIL
# Surefire captures System.out, so grep for the fail() assertion message instead.
# "Race condition detected" appears in surefire error output when the race is triggered.
# BUILD SUCCESS means no test failures (bug is fixed).
if echo "$MVN_OUTPUT" | grep -q "Race condition detected: getHandle() returned different LedgerDescriptor"; then
    echo ""
    echo "FAIL: Bug is present -- concurrent getHandle() calls return different LedgerDescriptor instances"
    rm -f "$TEST_DIR/HandleFactoryRaceTest.java"
    exit 1
elif echo "$MVN_OUTPUT" | grep -q "BUILD SUCCESS"; then
    echo ""
    echo "PASS: Bug is fixed -- concurrent getHandle() calls return the same LedgerDescriptor"
    rm -f "$TEST_DIR/HandleFactoryRaceTest.java"
    exit 0
elif echo "$MVN_OUTPUT" | grep -q "BUILD FAILURE"; then
    # BUILD FAILURE without our assertion message means compilation or other error
    echo ""
    echo "ERROR: Test failed to compile or run. Check output above."
    rm -f "$TEST_DIR/HandleFactoryRaceTest.java"
    exit 2
else
    echo ""
    echo "ERROR: Could not determine test result. Check output above."
    rm -f "$TEST_DIR/HandleFactoryRaceTest.java"
    exit 2
fi
