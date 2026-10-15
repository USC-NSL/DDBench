#!/usr/bin/env bash
# Reproduction and verification script for bookkeeper-4701-fencing-race
# Injects a JUnit test into the bookie package: two threads call
# HandleFactoryImpl.getHandle() for the same new ledger at the same time (500
# trials); both must get the same LedgerDescriptor.
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

TEST_DIR="$WORK_DIR/bookkeeper-server/src/test/java/org/apache/bookkeeper/bookie"
TEST_CLASS=DDBenchOracleHandleFactoryRaceTest
TEST_FILE="$TEST_DIR/$TEST_CLASS.java"
REPORT="$WORK_DIR/bookkeeper-server/target/surefire-reports/TEST-org.apache.bookkeeper.bookie.$TEST_CLASS.xml"
LOG="$RUN_DIR/mvn-test.log"

rebuild_worktree
[ -d "$WORK_DIR/bookkeeper-server" ] || error "bookkeeper-server not found in $WORK_DIR (run setup first)"
cd "$WORK_DIR"

echo "=== Reproducing bookkeeper-4701-fencing-race ==="

cleanup() {
    rm -f "$TEST_FILE"
    # Reports and classes compiled from the injected test must not outlive the run.
    rm -rf "$WORK_DIR/bookkeeper-server/target/surefire-reports"
    rm -f "$WORK_DIR"/bookkeeper-server/target/test-classes/org/apache/bookkeeper/bookie/DDBenchOracle*.class
}
trap cleanup EXIT

mkdir -p "$TEST_DIR"
cat > "$TEST_FILE" << 'TESTEOF'
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

public class DDBenchOracleHandleFactoryRaceTest {

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
                Throwable t = error1.get() != null ? error1.get() : error2.get();
                fail("concurrent getHandle() threw instead of returning a handle: " + t);
            }

            LedgerDescriptor h1 = handle1.get();
            LedgerDescriptor h2 = handle2.get();

            if (h1 == null || h2 == null) {
                fail("concurrent getHandle() returned null (t1 alive=" + t1.isAlive() + ", t2 alive=" + t2.isAlive() + ")");
            }
            if (h1 != h2) {
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

rm -rf bookkeeper-server/target/surefire-reports
echo "Running $TEST_CLASS (this may take 1-2 minutes)..."
mvn -pl bookkeeper-server test -Dtest="$TEST_CLASS" \
    -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip \
    -Dsurefire.useFile=false > "$LOG" 2>&1
tail -30 "$LOG"
junit_verdict "$REPORT" testConcurrentGetHandleReturnsSameInstance "$LOG" \
    "Bug is fixed — concurrent getHandle() calls return the same LedgerDescriptor" \
    "Bug is present — concurrent getHandle() calls returned different LedgerDescriptor instances"
