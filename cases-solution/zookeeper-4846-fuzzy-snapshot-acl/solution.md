# Solution: ZooKeeper #4846

- **Issue:** https://issues.apache.org/jira/browse/ZOOKEEPER-4846
- **Fix commit:** [`8532163df198466913f26141c0278dc11dbf53ab`](https://github.com/apache/zookeeper/commit/8532163df198466913f26141c0278dc11dbf53ab)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/apache/zookeeper/pull/2222
- **Commit:** `8532163df198466913f26141c0278dc11dbf53ab`

## Fix locus
- **Component:** DataTree node creation / fuzzy snapshot ACL recovery
- **Files:**
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/DataTree.java` (+3/-2)
  - `zookeeper-server/src/test/java/org/apache/zookeeper/server/DataTreeTest.java` (+16)

## Root cause

Fuzzy snapshots serialize the ACL map first, then znodes. This creates a race window where:

1. A znode exists with ACL reference `aclId` in the `ReferenceCountedACLCache`
2. Snapshot serialization begins: the ACL map is serialized at this point
3. The znode is deleted during the snapshot: `aclId` is removed from the cache via `removeUsage()` + `purgeUnused()`
4. The znode is recreated with the same ACL: the znode's `acl` field is set to the original `aclId`, but this time the reference count in the cache is independent
5. The znode is serialized into the snapshot referencing `aclId`

On restart, when loading the fuzzy snapshot:
- The ACL map is deserialized first (it does not contain `aclId` because it was purged before the znode was recreated)
- The znode is deserialized referencing `aclId` which no longer exists in the cache
- When `deleteNode()` is called (during `fastForwardFromEdits`), it tries to fetch the ACL via `convertLong_acl` using the missing `aclId`, which throws a fatal `RuntimeException`

## Diagnosis chain

1. **Runtime evidence:** ZooKeeper server fails to restart after loading a fuzzy snapshot with a fatal RuntimeException referencing a missing ACL in `ReferenceCountedACLCache.convertLong_acl`.

2. **Narrowing the subsystem:** The crash occurs during snapshot deserialization / replay in `DataTree`. The error is in the ACL cache lookup path.

3. **Code reasoning:** In `DataTree.createNode()`, when called during `fastForwardFromEdits` (replaying transactions on top of a fuzzy snapshot), a node may already exist with a stale ACL reference. The buggy code does not handle this case -- it assumes the ACL reference is always valid in the cache. The fix adds a defensive check: if the node already exists (throwing `NodeExistsException`), the code still ensures the ACL reference is restored in the cache.

4. **Confirmation:** The fix modifies `DataTree.createNode()` to defensively recover the ACL reference. When `fastForwardFromEdits` is true and a node already exists, the method re-adds the ACL to the cache before throwing `NodeExistsException`, ensuring subsequent operations on that node (including child creation) can look up the ACL successfully.

## Fix description

The fix modifies `DataTree.createNode()` to defensively handle missing ACL references:

1. When creating a node that already exists (the `NodeExistsException` path during `fastForwardFromEdits`), the method now re-adds the ACL to the cache before throwing the exception
2. This ensures that even if the ACL was purged during the fuzzy snapshot race, it is restored so subsequent operations (like child node creation) can access it
3. The change is minimal: 3 lines added, 2 lines removed in `DataTree.java`, plus a new test in `DataTreeTest.java`

## How to apply

```bash
git checkout 8532163df198466913f26141c0278dc11dbf53ab
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```
