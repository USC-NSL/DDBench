# Code Investigation

## What was searched
The symptom describes a server crash during startup with a RuntimeException about an invalid ACL during fuzzy snapshot recovery. Investigated how `createNode()` handles the `NodeExistsException` path and whether it properly maintains ACL cache references.

## What was found
```
$ sed -n '439,470p' zookeeper-server/src/main/java/org/apache/zookeeper/server/DataTree.java
    public void createNode(final String path, byte[] data, List<ACL> acl, ...) throws ... {
        ...
        synchronized (parent) {
            ...
            Long acls = aclCache.convertAcls(acl);   // <-- adds ACL to cache, gets new reference

            Set<String> children = parent.getChildren();
            if (children.contains(childName)) {
                throw new NodeExistsException();       // <-- throws WITHOUT updating existing node's ACL
            }
            ...
```

When replaying a create transaction during fuzzy snapshot recovery and the node already exists (from the snapshot), `createNode` calls `aclCache.convertAcls(acl)` to add the ACL to the cache, but when it detects the node already exists, it throws `NodeExistsException` without updating the existing node's `acl` field to the new cache reference.

The deserialization path shows why this matters:

```
$ sed -n '1347,1395p' zookeeper-server/src/main/java/org/apache/zookeeper/server/DataTree.java
    public void deserialize(InputArchive ia, String tag) throws IOException {
        aclCache.deserialize(ia);
        ...
        while (!"/".equals(path)) {
            DataNode node = new DataNode();
            ia.readRecord(node, "node");
            nodes.put(path, node);
            synchronized (node) {
                aclCache.addUsage(node.acl);        // <-- adds usage for snapshot ACL references
            }
            ...
        }
        ...
        aclCache.purgeUnused();                      // <-- purges ACLs with zero reference count
    }
```

During snapshot deserialization, `aclCache.purgeUnused()` is called at the end, which can remove ACL entries that have no references. If a node was created and deleted during the fuzzy snapshot window, the ACL used by that node's create transaction might be purged. When the create txn is replayed, the node exists in the snapshot (from a concurrent re-creation in a different session), but its ACL reference points to a purged entry. The `NodeExistsException` path doesn't update the node's ACL, leaving it with a dangling reference that causes a RuntimeException on the next access.

## Developer hypothesis
The `createNode` exception handling path for `NodeExistsException` and its interaction with the `aclCache.convertAcls` result and the existing node's ACL field.
