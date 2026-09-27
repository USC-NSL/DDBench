# Code Investigation

## What was searched
The symptom describes a follower that crashes during leader synchronization and later gets elected with incomplete transaction history. Investigated the NEWLEADER message handler in `Learner.syncWithLeader()` to understand the ordering of state updates.

## What was found
```
$ sed -n '733,780p' zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java
                case Leader.NEWLEADER: // Getting NEWLEADER here instead of in discovery
                    LOG.info("Learner received NEWLEADER message");
                    ...
                    if (snapshotNeeded) {
                        zk.takeSnapshot(syncSnapshot);
                    }

                    writeToTxnLog = true;
                    isPreZAB1_0 = false;

                    // ZOOKEEPER-3911: make sure sync the uncommitted logs before commit them (ACK NEWLEADER).
                    sock.setSoTimeout(self.tickTime * self.syncLimit);
                    self.setSyncMode(QuorumPeer.SyncMode.NONE);
                    zk.startupWithoutServing();              // <-- Step 1: starts ZK internals
                    if (zk instanceof FollowerZooKeeperServer) {
                        long startTime = Time.currentElapsedTime();
                        FollowerZooKeeperServer fzk = (FollowerZooKeeperServer) zk;
                        for (PacketInFlight p : packetsNotCommitted) {
                            final Request request = fzk.appendRequest(p.hdr, p.rec, p.digest);
                            requestsToAck.add(request);
                        }
                        fzk.getZKDatabase().commit();        // <-- Step 2: persist txns to disk
                        packetsNotCommitted.clear();
                    }

                    self.setCurrentEpoch(newEpoch);          // <-- Step 3: persist new epoch
                    writePacket(new QuorumPacket(Leader.ACK, newLeaderZxid, null, null), true);  // Step 4: ACK
```

The critical ordering is:
1. `zk.startupWithoutServing()` — initializes ZK server internals
2. Transaction persistence via `appendRequest` + `commit()`
3. `self.setCurrentEpoch(newEpoch)` — writes the new epoch to disk

If the follower crashes after step 1 but before step 2 completes, or after step 2 but before step 3, the follower restarts with an inconsistent state: it may have the new epoch on disk (from a snapshot taken earlier) but missing the committed transactions, or it may have transactions but not the epoch update.

## Developer hypothesis
The NEWLEADER handler's three disk-writing steps (`startupWithoutServing`, `appendRequest`/`commit`, and `setCurrentEpoch`) and the crash windows between them.
