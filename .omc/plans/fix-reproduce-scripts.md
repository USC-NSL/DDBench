# Plan: Fix Problematic reproduce.sh Scripts

## Requirements Summary

Seven `reproduce.sh` scripts use hardcoded patch checks, fix-commit dependencies, or fragile source-pattern matching instead of semantic behavioral verification. These must be rewritten so that any valid bug fix — not just the upstream fix — is correctly detected as PASS.

## Acceptance Criteria

1. Each fixed reproduce.sh must PASS when the upstream fix is applied and FAIL on the buggy commit
2. No reproduce.sh references a FIX_COMMIT hash for extracting production or test code
3. No reproduce.sh uses reflection/grep to detect specific field names, method names, or identifiers in source code as a proxy for "is the fix applied"
4. No reproduce.sh uses `sed -i` on production source files to inject accessor methods
5. All behavioral tests are self-contained: either inlined as heredocs in reproduce.sh or shipped as inject_test files in the case directory
6. Existing good patterns (cleanup traps, Docker mode preamble, REBUILD.sh support) are preserved

## Implementation Steps

### Step 1: `kafka-14334-delayed-fetch-purgatory` (CRITICAL — complete rewrite)

**File:** `cases/kafka-14334-delayed-fetch-purgatory/reproduce.sh`

**Current problem:** Uses Java reflection to check if field `partitionsWithNewHighWatermark` exists — a pure patch check, not behavioral.

**Fix approach:** Replace with a behavioral test that verifies the actual symptom: follower fetch requests hang for the full `fetch.max.wait.ms` timeout instead of completing promptly when new data is replicated.

Write a new test class `DelayedFetchPurgatoryBugTest.scala` (injected inline via heredoc) that:
1. Creates a `ReplicaFetcherThread` with a mock `ReplicaManager` and `DelayedOperationPurgatory`
2. Simulates a follower fetch cycle: `processPartitionData()` updates the follower's high watermark
3. After `processPartitionData()` returns, checks if `DelayedOperationPurgatory.tryCompleteElseWatch` was called (via a mock/spy)
4. On buggy code: the purgatory is never notified → test FAILs
5. On fixed code: the purgatory is notified → test PASSes

**Key detail:** The test should verify the *effect* (purgatory completion attempted after HW update) not the *mechanism* (specific field name). Use Mockito `verify()` on the ReplicaManager's `completeDelayedFetchRequests` or equivalent callback.

**Fallback approach:** If mocking the fetch thread internals is too complex across API versions, write a simpler test that:
1. Calls `assignPartitions` in a rack-aware scenario (same as kafka-15170's approach but testing the fetch path)
2. Asserts no `IllegalStateException` is thrown
3. The key is to test observable behavior, not internal field presence

### Step 2: `bookkeeper-2614-recovery-fencing-gap` (HIGH — remove git checkout dependency)

**File:** `cases/bookkeeper-2614-recovery-fencing-gap/reproduce.sh`

**Current problem:** `git checkout "$FIX_COMMIT" -- <5 test files>` pulls test infrastructure from a specific commit. These files may not compile with alternative fixes.

**Fix approach:** Inline the test as a self-contained Java file shipped in the case directory.

1. Create `cases/bookkeeper-2614-recovery-fencing-gap/inject_test.java` containing a standalone `LedgerRecoveryFencingTest.java`
2. The test should use the same behavioral assertion: a second writer (w2) recovers a ledger, then the first writer (w1) attempts to write — w1 must receive `BKLedgerFencedException`
3. Use only APIs available in the buggy commit (no fix-only test infrastructure like MockBookies/MockLedgerData)
4. Instead of the elaborate mock infrastructure from the fix commit, use BookKeeper's existing `BookieWriteLedgerTest` patterns with `TestBKConfiguration` and real/embedded bookies
5. Update reproduce.sh to copy inject_test.java into the test directory instead of `git checkout`
6. Remove the `git checkout -- PendingReadOp.java` line (line 29) which resets production code
7. Remove the FIX_COMMIT variable entirely

### Step 3: `nats-7718-subscription-leak` (MODERATE — inline the test)

**File:** `cases/nats-7718-subscription-leak/reproduce.sh`

**Current problem:** `git show "${FIX_COMMIT}:${TEST_FILE}"` extracts test from fix commit.

**Fix approach:** Inline the test function as a heredoc in reproduce.sh (same pattern used successfully by nats-7726, nats-6374, nats-7308).

1. Read the test function `TestJetStreamClusterLeakedSubsWithStreamImportOverlappingJetStreamSubs` from the fix commit (one-time manual extraction)
2. Embed it as a `cat >> "$TEST_FILE" << 'TESTEOF'` heredoc in reproduce.sh
3. Remove the FIX_COMMIT variable and `git show` extraction
4. Keep the existing backup/restore/cleanup pattern

The test is behavioral: it creates/destroys OrderedConsumers and checks subscription count via `/varz`. This works regardless of how the fix is implemented.

### Step 4: `nats-7852-filter-perf` (MODERATE — inline the test)

**File:** `cases/nats-7852-filter-perf/reproduce.sh`

**Current problem:** Same `git show FIX_COMMIT` pattern.

**Fix approach:** Same as Step 3 — inline `TestJetStreamConsumerSingleFilterSubjectInFilterSubjects` as a heredoc.

The test is behavioral: it compares delivery performance between filtered and unfiltered consumers. Works regardless of fix implementation.

### Step 5: `nats-7817-workqueue-message-loss` (MODERATE — inline the test)

**File:** `cases/nats-7817-workqueue-message-loss/reproduce.sh`

**Current problem:** Same `git show FIX_COMMIT` pattern.

**Fix approach:** Same as Step 3 — inline `TestJetStreamWQMaxDeliveryReached` as a heredoc.

The test is behavioral: it checks that WorkQueue messages aren't lost when consumers reach max-deliver. Works regardless of fix implementation.

### Step 6: `kafka-15170-endless-rebalance-loop` (LOW-MOD — remove sed injection)

**File:** `cases/kafka-15170-endless-rebalance-loop/reproduce.sh`

**Current problem:** `sed -i` on production code to inject accessor method, keyed on exact field declaration string.

**Fix approach:** Rewrite the test to verify the *observable outcome* rather than internal state:

1. Replace the current test with one that exercises the full rack-aware assignment path
2. Instead of checking `partitionsTransferringOwnership().size()`, verify that:
   - `assignPartitions()` completes without throwing `IllegalStateException`  
   - The returned assignment map has correct partition assignments for all consumers
   - No consumer is left with zero partitions (which triggers the infinite rebalance)
3. Remove the `sed -i` accessor injection (lines 46-52)
4. Remove the ASSIGNOR_FILE variable and backup logic
5. The test class is still injected via heredoc into CooperativeStickyAssignorTest.java

### Step 7: `kafka-15784-txn-offset-atomicity` (LOW-MOD — remove API detection)

**File:** `cases/kafka-15784-txn-offset-atomicity/reproduce.sh`

**Current problem:** `grep -q "verificationGuard"` branches based on source code content. The "fix" path runs tests by name that may not exist with alternative fixes.

**Fix approach:** Use only the behavioral mock test (current "buggy" path), with API-compatible compilation:

1. Keep the injected `TxnOffsetAtomicityTest.scala` which mocks `appendRecords` to throw and asserts atomicity
2. Make the test compile on both buggy and fixed API versions by using reflection for the `storeOffsets` call signature (similar to how consul-8377 uses reflection for API compat)
3. Remove the `grep -q "verificationGuard"` branching
4. Remove the "fix" path that runs upstream tests by name
5. The single behavioral test works for any fix: if the fix prevents in-memory state mutation before log append, `group.hasOffsets` will correctly be false after the exception

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Inlined NATS tests depend on helpers not in buggy commit | Test won't compile | Verify each test function's dependencies against the buggy commit's test helpers |
| Kafka behavioral tests may be hard to write without internal state access | Test may be incomplete | Fall back to a lighter assertion (e.g., no exception thrown) rather than checking internal state |
| BookKeeper test without MockBookies infra may be harder to set up | Complex test code | Use existing test patterns from the buggy commit's test suite |
| Inlined test code is harder to maintain | Future drift | Add comments noting the upstream test name and issue number for reference |

## Verification Steps

For each modified case:
1. `./bench.sh setup <case>` — verify setup still works
2. `./bench.sh reproduce <case>` — verify FAIL on buggy commit (bug detected)
3. Apply the upstream fix manually, then `./bench.sh reproduce <case>` — verify PASS
4. Confirm no FIX_COMMIT, `git show`, `git checkout <hash>`, reflection field checks, or `sed -i` on production code remain in reproduce.sh

## Execution Order

1. **kafka-14334** first (critical, complete rewrite needed)
2. **bookkeeper-2614** second (high severity, most complex)  
3. **nats-7718, nats-7852, nats-7817** in parallel (moderate, same pattern — inline heredoc)
4. **kafka-15170** and **kafka-15784** last (low-moderate, behavioral rewrites)
