# Code Investigation

## What was searched
The symptom describes a follower that crashes part-way through synchronizing with a new leader and, after restarting, can be elected leader despite missing committed transactions. Read how the follower handles the end of synchronization, i.e. the `NEWLEADER` case in `Learner.syncWithLeader()`.

## What was found
```
$ cat -n zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java | sed -n '733,782p'
   733	                case Leader.NEWLEADER: // Getting NEWLEADER here instead of in discovery
   734	                    // means this is Zab 1.0
   735	                    LOG.info("Learner received NEWLEADER message");
   736	                    if (qp.getData() != null && qp.getData().length > 1) {
   737	                        try {
   738	                            QuorumVerifier qv = self.configFromString(new String(qp.getData(), UTF_8));
   739	                            self.setLastSeenQuorumVerifier(qv, true);
   740	                            newLeaderQV = qv;
   741	                        } catch (Exception e) {
   742	                            e.printStackTrace();
   743	                        }
   744	                    }
   745	
   746	                    if (snapshotNeeded) {
   747	                        zk.takeSnapshot(syncSnapshot);
   748	                    }
   749	
   750	
   751	                    writeToTxnLog = true;
   752	                    //Anything after this needs to go to the transaction log, not applied directly in memory
   753	                    isPreZAB1_0 = false;
   754	
   755	                    // ZOOKEEPER-3911: make sure sync the uncommitted logs before commit them (ACK NEWLEADER).
   756	                    sock.setSoTimeout(self.tickTime * self.syncLimit);
   757	                    self.setSyncMode(QuorumPeer.SyncMode.NONE);
   758	                    zk.startupWithoutServing();
   759	                    if (zk instanceof FollowerZooKeeperServer) {
   760	                        long startTime = Time.currentElapsedTime();
   761	                        FollowerZooKeeperServer fzk = (FollowerZooKeeperServer) zk;
   762	                        for (PacketInFlight p : packetsNotCommitted) {
   763	                            final Request request = fzk.appendRequest(p.hdr, p.rec, p.digest);
   764	                            requestsToAck.add(request);
   765	                        }
   766	
   767	                        // persist the txns to disk
   768	                        fzk.getZKDatabase().commit();
   769	                        LOG.info("{} txns have been persisted and it took {}ms",
   770	                        packetsNotCommitted.size(), Time.currentElapsedTime() - startTime);
   771	                        packetsNotCommitted.clear();
   772	                    }
   773	
   774	                    // set the current epoch after all the tnxs are persisted
   775	                    self.setCurrentEpoch(newEpoch);
   776	                    LOG.info("Set the current epoch to {}", newEpoch);
   777	
   778	                    // send NEWLEADER ack after all the tnxs are persisted
   779	                    writePacket(new QuorumPacket(Leader.ACK, newLeaderZxid, null, null), true);
   780	                    LOG.info("Sent NEWLEADER ack to leader with zxid {}", Long.toHexString(newLeaderZxid));
   781	                    break;
   782	                }
```

## Developer hypothesis
The `NEWLEADER` handler performs several steps that update the follower's persistent state (snapshot, transaction log, current epoch) before acknowledging the leader. These steps have ordering dependencies that could matter if the follower crashes in the middle of synchronization.
