# Code Investigation

## What was searched
The symptom describes a server failing to start after loading a fuzzy snapshot, with a fatal `RuntimeException` from an ACL lookup for a znode, associated with creates and deletes that ran while the snapshot was being taken. Searched for how `DataTree` maintains its ACL cache, and read node creation (`createNode`) and snapshot deserialization (`deserialize`).

## What was found
```
$ grep -n "aclCache\." zookeeper-server/src/main/java/org/apache/zookeeper/server/DataTree.java
463:            Long acls = aclCache.convertAcls(acl);
570:            aclCache.removeUsage(node.acl);
769:            aclCache.removeUsage(n.acl);
772:            n.acl = aclCache.convertAcls(acl);
788:            return new ArrayList<>(aclCache.convertLong(n.acl));
794:            return aclCache.convertLong(node.acl);
799:        return aclCache.size();
1330:        aclCache.serialize(oa);
1348:        aclCache.deserialize(ia);
1358:                aclCache.addUsage(node.acl);
1395:        aclCache.purgeUnused();
```

```
$ cat -n zookeeper-server/src/main/java/org/apache/zookeeper/server/DataTree.java | sed -n '439,503p'
   439	    public void createNode(final String path, byte[] data, List<ACL> acl, long ephemeralOwner, int parentCVersion, long zxid, long time, Stat outputStat) throws NoNodeException, NodeExistsException {
   440	        int lastSlash = path.lastIndexOf('/');
   441	        String parentName = path.substring(0, lastSlash);
   442	        String childName = path.substring(lastSlash + 1);
   443	        StatPersisted stat = createStat(zxid, time, ephemeralOwner);
   444	        DataNode parent = nodes.get(parentName);
   445	        if (parent == null) {
   446	            throw new NoNodeException();
   447	        }
   448	        List<ACL> parentAcl;
   449	        synchronized (parent) {
   450	            parentAcl = getACL(parent);
   451	
   452	            // Add the ACL to ACL cache first, to avoid the ACL not being
   453	            // created race condition during fuzzy snapshot sync.
   454	            //
   455	            // This is the simplest fix, which may add ACL reference count
   456	            // again if it's already counted in the ACL map of fuzzy
   457	            // snapshot, which might also happen for deleteNode txn, but
   458	            // at least it won't cause the ACL not exist issue.
   459	            //
   460	            // Later we can audit and delete all non-referenced ACLs from
   461	            // ACL map when loading the snapshot/txns from disk, like what
   462	            // we did for the global sessions.
   463	            Long acls = aclCache.convertAcls(acl);
   464	
   465	            Set<String> children = parent.getChildren();
   466	            if (children.contains(childName)) {
   467	                throw new NodeExistsException();
   468	            }
   469	
   470	            nodes.preChange(parentName, parent);
   471	            if (parentCVersion == -1) {
   472	                parentCVersion = parent.stat.getCversion();
   473	                parentCVersion++;
   474	            }
   475	            // There is possibility that we'll replay txns for a node which
   476	            // was created and then deleted in the fuzzy range, and it's not
   477	            // exist in the snapshot, so replay the creation might revert the
   478	            // cversion and pzxid, need to check and only update when it's
   479	            // larger.
   480	            if (parentCVersion > parent.stat.getCversion()) {
   481	                parent.stat.setCversion(parentCVersion);
   482	                parent.stat.setPzxid(zxid);
   483	            }
   484	            DataNode child = new DataNode(data, acls, stat);
   485	            parent.addChild(childName);
   486	            nodes.postChange(parentName, parent);
   487	            nodeDataSize.addAndGet(getNodeSize(path, child.data));
   488	            nodes.put(path, child);
   489	            EphemeralType ephemeralType = EphemeralType.get(ephemeralOwner);
   490	            if (ephemeralType == EphemeralType.CONTAINER) {
   491	                containers.add(path);
   492	            } else if (ephemeralType == EphemeralType.TTL) {
   493	                ttls.add(path);
   494	            } else if (ephemeralOwner != 0) {
   495	                HashSet<String> list = ephemerals.computeIfAbsent(ephemeralOwner, k -> new HashSet<>());
   496	                synchronized (list) {
   497	                    list.add(path);
   498	                }
   499	            }
   500	            if (outputStat != null) {
   501	                child.copyStat(outputStat);
   502	            }
   503	        }
```

```
$ cat -n zookeeper-server/src/main/java/org/apache/zookeeper/server/DataTree.java | sed -n '1347,1397p'
  1347	    public void deserialize(InputArchive ia, String tag) throws IOException {
  1348	        aclCache.deserialize(ia);
  1349	        nodes.clear();
  1350	        pTrie.clear();
  1351	        nodeDataSize.set(0);
  1352	        String path = ia.readString("path");
  1353	        while (!"/".equals(path)) {
  1354	            DataNode node = new DataNode();
  1355	            ia.readRecord(node, "node");
  1356	            nodes.put(path, node);
  1357	            synchronized (node) {
  1358	                aclCache.addUsage(node.acl);
  1359	            }
  1360	            int lastSlash = path.lastIndexOf('/');
  1361	            if (lastSlash == -1) {
  1362	                root = node;
  1363	            } else {
  1364	                String parentPath = path.substring(0, lastSlash);
  1365	                DataNode parent = nodes.get(parentPath);
  1366	                if (parent == null) {
  1367	                    throw new IOException(
  1368	                            "Invalid Datatree, unable to find parent " + parentPath + " of path " + path);
  1369	                }
  1370	                parent.addChild(path.substring(lastSlash + 1));
  1371	                long owner = node.stat.getEphemeralOwner();
  1372	                EphemeralType ephemeralType = EphemeralType.get(owner);
  1373	                if (ephemeralType == EphemeralType.CONTAINER) {
  1374	                    containers.add(path);
  1375	                } else if (ephemeralType == EphemeralType.TTL) {
  1376	                    ttls.add(path);
  1377	                } else if (owner != 0) {
  1378	                    HashSet<String> list = ephemerals.computeIfAbsent(owner, k -> new HashSet<>());
  1379	                    list.add(path);
  1380	                }
  1381	            }
  1382	            path = ia.readString("path");
  1383	        }
  1384	        // have counted digest for root node with "", ignore here to avoid
  1385	        // counting twice for root node
  1386	        nodes.putWithoutDigest("/", root);
  1387	
  1388	        nodeDataSize.set(approximateDataSize());
  1389	
  1390	        // we are done with deserializing the datatree
  1391	        // update the quotas - create path trie
  1392	        // and also update the stat nodes
  1393	        setupQuota();
  1394	
  1395	        aclCache.purgeUnused();
  1396	    }
  1397	
```

## Developer hypothesis
ACL cache entries are reference-counted and adjusted both when a snapshot is deserialized and when transactions are replayed on top of it. Worth checking how replaying transactions that overlap with a fuzzy snapshot affects those reference counts and the ACL references held by existing nodes.
