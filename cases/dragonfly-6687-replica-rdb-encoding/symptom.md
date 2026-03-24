# Symptom

When replicating from a Dragonfly master that has tiered storage enabled, the replica fails to sync with the error:

```
Unknown RDB string encoding 62
```

## Observable behavior
- The replica enters a retry loop, repeatedly attempting to sync and failing with the same error.
- The replica never successfully completes initial synchronization.
- The issue is observed when the master has tiered storage enabled and certain data loaded.
