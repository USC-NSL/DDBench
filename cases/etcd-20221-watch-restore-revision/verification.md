# Verification: etcd #20221

```bash
#!/bin/bash

cd etcd
go test -v -run "^TestWatchRestoreFutureRevisionBug$" -count=1 -timeout 60s ./server/storage/mvcc/
```

- **FAIL:** The test fails with a message indicating the watcher received events with revisions below the requested future start revision. This confirms the bug is present.

  ```
  FAIL: watcher received event with revision 2, but requested start revision was 100 — watch contract violated after restore
  ```

- **PASS:** The test passes, confirming that the watcher correctly does not deliver events with revisions below its requested start revision after a snapshot restore.

  ```
  PASS: watcher did not receive any events below the requested future revision 100
  ```
