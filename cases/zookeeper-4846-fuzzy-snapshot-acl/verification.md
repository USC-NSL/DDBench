# Verification: ZooKeeper #4846

```bash
# Inject regression test into DataTreeTest.java and run it
cd zookeeper-server
mvn test -Dtest="DataTreeTest#testCreateNodeFixMissingACL" -DfailIfNoTests=false -q
```

- **FAIL:** Test fails with a `RuntimeException` when creating a child node -- the parent's ACL reference was removed from the cache (simulating the fuzzy snapshot race), and `createNode` does not defensively recover the missing ACL. This is the bug.
- **PASS:** Test passes -- `createNode` defensively recovers the missing ACL when it encounters a node with a stale ACL reference during `fastForwardFromEdits`. The child node is created successfully.
