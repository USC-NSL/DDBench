# Code Investigation

## What was searched
The symptom describes inconsistency after a stale follower becomes leader. Investigated how transactions are added to the `committedLog` during different processing paths.

## What was found
There are two `processTxn` overloads in `ZooKeeperServer`:

```
$ sed -n '1850,1854p' zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java
    public ProcessTxnResult processTxn(TxnHeader hdr, Record txn) {
        processTxnForSessionEvents(null, hdr, txn);
        return processTxnInDB(hdr, txn, null);
    }
```

This overload (called from `Learner.syncWithLeader()` during follower sync at lines 669, 710, 784) processes the transaction in the DataTree but does NOT call `addCommittedProposal()`.

```
$ sed -n '1856,1893p' zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java
    // entry point for FinalRequestProcessor.java
    public ProcessTxnResult processTxn(Request request) {
        ...
        synchronized (outstandingChanges) {
            ProcessTxnResult rc = processTxnInDB(hdr, request.getTxn(), request.getTxnDigest());
            ...
            // do not add non quorum packets to the queue.
            if (quorumRequest) {
                getZKDatabase().addCommittedProposal(request);
            }
            return rc;
        }
    }
```

This overload (called from `FinalRequestProcessor` for normal request processing) DOES call `addCommittedProposal(request)`, which adds the transaction to `committedLog`.

The `committedLog` is used by the leader to perform diff-based sync with followers:

```
$ grep -n 'committedLog' zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java
95:    protected Queue<Proposal> committedLog = new ArrayDeque<>();
230:            result = this.committedLog;
```

## Developer hypothesis
The two `processTxn` overloads and their respective post-`processTxnInDB` paths, particularly the `addCommittedProposal` call site.
