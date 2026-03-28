# Symptom

When `repl-namespace-enabled` is turned on, a slave that restarts after downtime silently loses key updates that occurred on the master while the slave was offline.

## Observable behavior

- The slave reconnects to the master and replication status shows `master_link_status:up`.
- No errors appear in either master or slave logs.
- Keys that were updated or created on the master during the slave's downtime are stale or missing on the slave.
- New keys written to the master after the slave reconnects replicate correctly.
- The replication gap is silent -- there is no indication that data was skipped.
