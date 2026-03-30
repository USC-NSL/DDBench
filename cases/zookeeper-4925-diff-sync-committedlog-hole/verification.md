# Verification: ZooKeeper #4925

```bash
# Inject regression test and run it
cd zookeeper-server
mvn test -Dtest="QuorumSyncTest#testStaleDiffSync" -DfailIfNoTests=false -q
```

- **FAIL:** Test assertion fails — after a stale follower rejoins via DIFF sync and later becomes leader, committed znodes (`/foo0`..`/foo9`, `/bar0`..`/bar9`) are not found. The `committedLog` hole causes the leader to serve incomplete DIFF syncs to other stale nodes, resulting in silent data loss.
- **PASS:** Test passes — all committed znodes are present on all nodes after leader failover and DIFF sync. The `committedLog` is properly populated during SYNCHRONIZATION, and no data is lost.
