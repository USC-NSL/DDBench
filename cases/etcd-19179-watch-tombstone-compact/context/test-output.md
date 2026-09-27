# Test Output

Obtained by running `cd server && go test -v -timeout 60s ./storage/mvcc/` against the buggy build.

## Output

```
=== RUN   TestHashByRevValue
--- PASS: TestHashByRevValue (0.38s)
=== RUN   TestHashByRevValueLastRevision
--- PASS: TestHashByRevValueLastRevision (0.31s)
=== RUN   TestCompactionHash
--- PASS: TestCompactionHash (0.34s)
=== RUN   TestHasherStore
--- PASS: TestHasherStore (0.00s)
=== RUN   TestHasherStoreFull
--- PASS: TestHasherStoreFull (0.00s)
=== RUN   TestIndexGet
--- PASS: TestIndexGet (0.00s)
=== RUN   TestIndexRange
--- PASS: TestIndexRange (0.00s)
=== RUN   TestIndexTombstone
--- PASS: TestIndexTombstone (0.00s)
=== RUN   TestIndexRevision
--- PASS: TestIndexRevision (0.00s)
=== RUN   TestIndexCompactAndKeep
--- PASS: TestIndexCompactAndKeep (0.00s)
=== RUN   TestKeyIndexGet
--- PASS: TestKeyIndexGet (0.00s)
=== RUN   TestKeyIndexSince
--- PASS: TestKeyIndexSince (0.00s)
=== RUN   TestKeyIndexPut
--- PASS: TestKeyIndexPut (0.00s)
=== RUN   TestKeyIndexRestore
--- PASS: TestKeyIndexRestore (0.00s)
=== RUN   TestKeyIndexTombstone
--- PASS: TestKeyIndexTombstone (0.00s)
=== RUN   TestKeyIndexCompactAndKeep
--- PASS: TestKeyIndexCompactAndKeep (0.00s)
=== RUN   TestKeyIndexCompactOnFurtherRev
--- PASS: TestKeyIndexCompactOnFurtherRev (0.00s)
=== RUN   TestKeyIndexIsEmpty
--- PASS: TestKeyIndexIsEmpty (0.00s)
=== RUN   TestKeyIndexFindGeneration
--- PASS: TestKeyIndexFindGeneration (0.00s)
=== RUN   TestKeyIndexLess
--- PASS: TestKeyIndexLess (0.00s)
=== RUN   TestGenerationIsEmpty
--- PASS: TestGenerationIsEmpty (0.00s)
=== RUN   TestGenerationWalk
--- PASS: TestGenerationWalk (0.00s)
=== RUN   TestKVRange
--- PASS: TestKVRange (0.00s)
=== RUN   TestKVTxnRange
--- PASS: TestKVTxnRange (0.00s)
=== RUN   TestKVRangeRev
--- PASS: TestKVRangeRev (0.00s)
=== RUN   TestKVTxnRangeRev
--- PASS: TestKVTxnRangeRev (0.00s)
=== RUN   TestKVRangeBadRev
--- PASS: TestKVRangeBadRev (0.01s)
=== RUN   TestKVTxnRangeBadRev
--- PASS: TestKVTxnRangeBadRev (0.01s)
=== RUN   TestKVRangeLimit
--- PASS: TestKVRangeLimit (0.00s)
=== RUN   TestKVTxnRangeLimit
--- PASS: TestKVTxnRangeLimit (0.01s)
=== RUN   TestKVPutMultipleTimes
--- PASS: TestKVPutMultipleTimes (0.01s)
=== RUN   TestKVTxnPutMultipleTimes
--- PASS: TestKVTxnPutMultipleTimes (0.01s)
=== RUN   TestKVDeleteRange
--- PASS: TestKVDeleteRange (0.03s)
=== RUN   TestKVTxnDeleteRange
--- PASS: TestKVTxnDeleteRange (0.02s)
=== RUN   TestKVDeleteMultipleTimes
--- PASS: TestKVDeleteMultipleTimes (0.01s)
=== RUN   TestKVTxnDeleteMultipleTimes
--- PASS: TestKVTxnDeleteMultipleTimes (0.00s)
=== RUN   TestKVPutWithSameLease
--- PASS: TestKVPutWithSameLease (0.00s)
=== RUN   TestKVTxnPutWithSameLease
--- PASS: TestKVTxnPutWithSameLease (0.00s)
=== RUN   TestKVOperationInSequence
--- PASS: TestKVOperationInSequence (0.01s)
=== RUN   TestKVTxnBlockWriteOperations
--- PASS: TestKVTxnBlockWriteOperations (0.03s)
=== RUN   TestKVTxnNonBlockRange
--- PASS: TestKVTxnNonBlockRange (0.00s)
=== RUN   TestKVTxnOperationInSequence
--- PASS: TestKVTxnOperationInSequence (0.01s)
=== RUN   TestKVCompactReserveLastValue
--- PASS: TestKVCompactReserveLastValue (0.01s)
=== RUN   TestKVCompactBad
--- PASS: TestKVCompactBad (0.01s)
=== RUN   TestKVHash
--- PASS: TestKVHash (0.01s)
=== RUN   TestKVRestore
--- PASS: TestKVRestore (0.05s)
=== RUN   TestKVSnapshot
--- PASS: TestKVSnapshot (0.01s)
=== RUN   TestWatchableKVWatch
--- PASS: TestWatchableKVWatch (0.11s)
=== RUN   TestScheduleCompaction
--- PASS: TestScheduleCompaction (0.02s)
=== RUN   TestCompactAllAndRestore
--- PASS: TestCompactAllAndRestore (0.01s)
=== RUN   TestStoreRev
--- PASS: TestStoreRev (0.00s)
=== RUN   TestStorePut
--- PASS: TestStorePut (0.00s)
=== RUN   TestStoreRange
--- PASS: TestStoreRange (0.00s)
=== RUN   TestStoreDeleteRange
--- PASS: TestStoreDeleteRange (0.00s)
=== RUN   TestStoreCompact
--- PASS: TestStoreCompact (0.00s)
=== RUN   TestStoreRestore
--- PASS: TestStoreRestore (0.00s)
=== RUN   TestRestoreDelete
--- PASS: TestRestoreDelete (0.01s)
=== RUN   TestRestoreContinueUnfinishedCompaction
=== RUN   TestRestoreContinueUnfinishedCompaction/recreate
=== RUN   TestRestoreContinueUnfinishedCompaction/restore
--- PASS: TestRestoreContinueUnfinishedCompaction (0.22s)
=== RUN   TestHashKVWhenCompacting
--- PASS: TestHashKVWhenCompacting (2.74s)
=== RUN   TestHashKVWithCompactedAndFutureRevisions
--- PASS: TestHashKVWithCompactedAndFutureRevisions (0.84s)
=== RUN   TestHashKVZeroRevision
--- PASS: TestHashKVZeroRevision (0.79s)
=== RUN   TestTxnPut
--- PASS: TestTxnPut (0.01s)
=== RUN   TestConcurrentReadNotBlockingWrite
--- PASS: TestConcurrentReadNotBlockingWrite (0.00s)
=== RUN   TestConcurrentReadTxAndWrite
--- PASS: TestConcurrentReadTxAndWrite (0.11s)
=== RUN   TestScheduledCompact
=== RUN   TestScheduledCompact/1
=== RUN   TestScheduledCompact/0
=== RUN   TestScheduledCompact/9223372036854775807
--- PASS: TestScheduledCompact (0.04s)
=== RUN   TestFinishedCompact
=== RUN   TestFinishedCompact/1
=== RUN   TestFinishedCompact/0
=== RUN   TestFinishedCompact/9223372036854775807
--- PASS: TestFinishedCompact (0.04s)
=== RUN   TestWatch
--- PASS: TestWatch (0.00s)
=== RUN   TestNewWatcherCancel
--- PASS: TestNewWatcherCancel (0.00s)
=== RUN   TestCancelUnsynced
--- PASS: TestCancelUnsynced (0.01s)
=== RUN   TestSyncWatchers
--- PASS: TestSyncWatchers (0.01s)
=== RUN   TestRangeEvents
=== RUN   TestRangeEvents/0_rangeEvents(2,_6)
=== RUN   TestRangeEvents/1_rangeEvents(2,_5)
=== RUN   TestRangeEvents/2_rangeEvents(2,_4)
=== RUN   TestRangeEvents/3_rangeEvents(2,_3)
=== RUN   TestRangeEvents/4_rangeEvents(2,_2)
=== RUN   TestRangeEvents/5_rangeEvents(2,_6)
=== RUN   TestRangeEvents/6_rangeEvents(3,_6)
=== RUN   TestRangeEvents/7_rangeEvents(4,_6)
=== RUN   TestRangeEvents/8_rangeEvents(5,_6)
=== RUN   TestRangeEvents/9_rangeEvents(6,_6)
=== RUN   TestRangeEvents/10_rangeEvents(2,_2)
=== RUN   TestRangeEvents/11_rangeEvents(2,_3)
=== RUN   TestRangeEvents/12_rangeEvents(2,_4)
=== RUN   TestRangeEvents/13_rangeEvents(3,_4)
=== RUN   TestRangeEvents/14_rangeEvents(3,_5)
=== RUN   TestRangeEvents/15_rangeEvents(4,_5)
=== RUN   TestRangeEvents/16_rangeEvents(4,_6)
=== RUN   TestRangeEvents/17_rangeEvents(5,_6)
=== RUN   TestRangeEvents/18_rangeEvents(6,_6)
--- PASS: TestRangeEvents (0.01s)
=== RUN   TestWatchCompacted
--- PASS: TestWatchCompacted (0.11s)
=== RUN   TestWatchNoEventLossOnCompact
--- PASS: TestWatchNoEventLossOnCompact (0.11s)
=== RUN   TestWatchFutureRev
--- PASS: TestWatchFutureRev (0.01s)
=== RUN   TestWatchRestore
=== RUN   TestWatchRestore/Normal
=== RUN   TestWatchRestore/RunSyncWatchLoopBeforeRestore
--- PASS: TestWatchRestore (2.14s)
=== RUN   TestWatchRestoreSyncedWatcher
--- PASS: TestWatchRestoreSyncedWatcher (2.01s)
=== RUN   TestWatchBatchUnsynced
=== RUN   TestWatchBatchUnsynced/3_revisions,_4_revs_per_batch,_1_events_per_revision
=== RUN   TestWatchBatchUnsynced/3_revisions,_4_revs_per_batch,_3_events_per_revision
--- PASS: TestWatchBatchUnsynced (0.62s)
=== RUN   TestNewMapwatcherToEventMap
--- PASS: TestNewMapwatcherToEventMap (0.00s)
=== RUN   TestWatchVictims
--- PASS: TestWatchVictims (0.53s)
=== RUN   TestStressWatchCancelClose
--- PASS: TestStressWatchCancelClose (0.04s)
=== RUN   TestWatcherWatchID
--- PASS: TestWatcherWatchID (1.02s)
=== RUN   TestWatcherRequestsCustomID
--- PASS: TestWatcherRequestsCustomID (0.01s)
=== RUN   TestWatcherWatchPrefix
--- PASS: TestWatcherWatchPrefix (0.51s)
=== RUN   TestWatcherWatchWrongRange
--- PASS: TestWatcherWatchWrongRange (0.01s)
=== RUN   TestWatchDeleteRange
--- PASS: TestWatchDeleteRange (0.00s)
=== RUN   TestWatchStreamCancelWatcherByID
--- PASS: TestWatchStreamCancelWatcherByID (0.00s)
=== RUN   TestWatcherRequestProgress
--- PASS: TestWatcherRequestProgress (0.01s)
=== RUN   TestWatcherRequestProgressAll
--- PASS: TestWatcherRequestProgressAll (0.01s)
=== RUN   TestWatcherWatchWithFilter
--- PASS: TestWatcherWatchWithFilter (0.11s)
PASS
ok  	go.etcd.io/etcd/server/v3/storage/mvcc	13.497s
```

All existing mvcc tests pass. No test covers the scenario where compaction removes the put revision, leaving only a tombstone, and then the server restarts and must restore the index from the remaining tombstone-only entry.
