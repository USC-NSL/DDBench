# Verification: etcd #17158

```bash
#!/bin/bash

cd etcd
go test -v -run "^TestRangeAfterDeleteMatch$" -count=1 -timeout 60s ./server/storage/backend/
```

- **FAIL:** The test fails because after deleting a key, `ReadTx.UnsafeRange` still returns the deleted key while `BatchTx.UnsafeRange` correctly returns nothing. This confirms the bug is present: delete operations bypass the read buffer, causing stale reads that violate linearizability.

  ```
  FAIL: keys on read and batch transaction don't match after delete
  ```

- **PASS:** The test passes, confirming that after a delete, both `BatchTx` and `ReadTx` agree the key is gone. The fix forces an immediate bbolt commit when there are pending delete operations, ensuring the read path reflects the deletion.

  ```
  ok  	go.etcd.io/etcd/server/v3/storage/backend
  ```
