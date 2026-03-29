# Verification: etcd #19179

```bash
#!/bin/bash

cd etcd
go test -v -run "^TestRestoreTombstoneAfterCompaction$" -count=1 -timeout 120s ./server/storage/mvcc/
```

- **FAIL:** The test fails because after restore, the key index is missing the tombstone for the deleted key. The `restoreIntoIndex` function skips tombstones that are the only remaining revision for a key.

  ```
  Bug present — foo1 has NO key index entry after restore. The tombstone at rev 7 was not
  reconstructed during restoreIntoIndex.
  ```

- **PASS:** The test passes, confirming that the tombstone is correctly restored into the key index after compaction and restart.

  ```
  OK: foo1 key index correctly restored with tombstone at rev 7
  ```
