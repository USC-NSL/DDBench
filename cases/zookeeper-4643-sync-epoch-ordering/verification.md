# Verification: ZooKeeper #4643

```bash
# Inject regression test into Zab1_0Test.java and run it
cd zookeeper-server
mvn test -Dtest="Zab1_0Test#testNormalFollowerRun_ProcessCommitInSyncAfterAckNewLeader"
```

- **FAIL:** Test assertion fails — uncommitted proposals are persisted to disk during NEWLEADER processing, `lastZxid` in the transaction log includes the uncommitted proposal's zxid instead of only the committed zxid. This means a follower that crashes after epoch update but before transaction persistence could lose committed data.
- **PASS:** Test passes — only committed transactions are persisted to disk during NEWLEADER processing, the epoch is updated after persistence, and the transaction log reflects only committed data.
