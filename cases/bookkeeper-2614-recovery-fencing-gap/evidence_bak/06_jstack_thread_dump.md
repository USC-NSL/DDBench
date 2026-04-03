# Evidence: Thread Dump During Deadlocked Test

## Source
`jstack` output captured when the test hangs at the assertion point (Step 10), showing the state of writer threads and their relationship to the recovery protocol.

## Command
```bash
jstack $(jps | grep surefire | awk '{print $1}')
```

## Relevant Thread Excerpts

### Main Test Thread (waiting for w1 write future)
```
"main" #1 prio=5 os_prio=0 tid=0x00007f8b14001800 nid=0x1a23 waiting on condition
   java.lang.Thread.State: TIMED_WAITING (parking)
	at jdk.internal.misc.Unsafe.park(Native Method)
	at java.util.concurrent.locks.LockSupport.parkNanos(LockSupport.java:234)
	at java.util.concurrent.CompletableFuture.timedGet(CompletableFuture.java:1886)
	at java.util.concurrent.CompletableFuture.get(CompletableFuture.java:2021)
	at org.apache.bookkeeper.client.LedgerRecovery2Test.testFirstWriterCannotCommitWriteAfter2ndWriterCloses(LedgerRecovery2Test.java:471)

   Locked ownable synchronizers: None
```

### w1 Write Callback Thread (completed successfully — bug manifestation)
```
"OrderedExecutor-0-0" #14 prio=5 os_prio=0 tid=0x00007f8b14234000 nid=0x1a30 runnable
   java.lang.Thread.State: RUNNABLE
	at org.apache.bookkeeper.client.PendingAddOp.writeComplete(PendingAddOp.java:268)
	at org.apache.bookkeeper.proto.MockBookieClient.lambda$addEntry$1(MockBookieClient.java:188)
	at java.util.concurrent.CompletableFuture.uniWhenComplete(CompletableFuture.java:863)

   // Write callback for b2 returned OK (not fenced), completing the ack quorum
```

### w2 Recovery Thread (already completed)
```
"OrderedExecutor-1-0" #15 prio=5 os_prio=0 tid=0x00007f8b14235800 nid=0x1a31 waiting on condition
   java.lang.Thread.State: WAITING (parking)
	at jdk.internal.misc.Unsafe.park(Native Method)
	at java.util.concurrent.CompletableFuture.get(CompletableFuture.java:1907)
	// w2 recovery already completed and closed the ledger
```

## Interpretation
The thread dump shows that w1's write to b2 completes successfully via `PendingAddOp.writeComplete()` returning `BKException.Code.OK`. The write was not rejected because b2's `MockLedgerData.isFenced` is `false` — b2 was never fenced. The recovery (w2) thread has already completed, having closed the ledger without seeing e2. The main test thread times out waiting for the expected `BKLedgerFencedException` that never arrives.
