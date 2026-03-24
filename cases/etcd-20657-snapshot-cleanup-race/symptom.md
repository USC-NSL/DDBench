# Symptom

A follower node in a multi-node etcd cluster panics with a "file not found" error when trying to read a snapshot `.snap.db` file. This occurs during periods of rapid leader changes combined with continuous writes when `--snapshot-count` is set to a low value (e.g., 2).

The panic message is similar to:
```
panic: open /tmp/etcd-nodeX/member/snap/0000000000000XXX-0000000000000XXX.snap.db: no such file or directory
```

The issue is a race condition: the snapshot cleanup logic removes an older `.snap.db` file that it considers "orphaned," but the snapshot application path is still actively reading that same file. The cleanup and application happen concurrently without synchronization.

This is intermittent and depends on timing — it happens more frequently under high write throughput with a very low snapshot count, which forces frequent snapshot creation and cleanup.
