# Verification: etcd #17529

```bash
#!/bin/bash

cd etcd
go test -v -run "^TestWatchNoEventLossOnCompactBug$" -count=1 -timeout 120s ./server/storage/mvcc/
```

- **FAIL:** The test fails with a timeout or assertion error indicating that one or more watchers never received their compaction notification. This confirms the bug is present: the watcher's revision was silently advanced past the compaction point, permanently losing the notification.

  ```
  FAIL: timed out waiting for all watchers to complete — watcher(s) stuck without compaction notification or events
  ```

- **PASS:** The test passes, confirming that all compacted watchers eventually receive their compaction notification and all above-compaction watchers receive their events normally.

  ```
  OK: all watchers completed — compacted watchers received compaction notifications, synced watcher received all events
  ```
