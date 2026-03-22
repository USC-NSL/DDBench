# Symptom: Dragonfly #6687

When replicating from a Dragonfly master that has tiered storage enabled, the replica fails to sync with the error:

```
Unknown RDB string encoding 62
```

The replica then enters a retry loop, repeatedly attempting to sync and failing with the same error. The replica never successfully completes initial synchronization.

This occurs specifically when the master has data that was loaded from a Redis 6 RDB backup and tiered storage is enabled, causing some entries to be in a "delayed" state in the DashTable.
