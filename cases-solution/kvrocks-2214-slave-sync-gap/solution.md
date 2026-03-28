# Solution: Kvrocks #2214

## Fix
- **PR:** https://github.com/apache/kvrocks/pull/2221
- **Commit:** `7e1b797920517edf9c798cd4b440789b524d7956`

## Fix locus
- **Component:** Namespace rewrite logic / replication offset tracking
- **Files:** `src/server/namespace.cc`, `src/storage/redis_pubsub.cc`, `src/storage/storage.cc`

## Diagnosis chain
1. **Runtime evidence:** After restarting a slave, keys updated on the master during the slave's downtime are missing on the slave, but keys written after the slave comes back online replicate correctly. This indicates a replication offset mismatch.
2. **Narrowing the component:** The slave's replication INFO shows that the offset is higher than expected after restart. This points to something incrementing the sequence number during startup, before replication resumes.
3. **Code-level reasoning:** With `repl-namespace-enabled=yes`, the server rewrites namespace data to RocksDB on startup. Each write increments the RocksDB sequence number. This extra sequence increment causes the incremental replication to skip entries that the master sent during the slave's downtime. The fix guards the namespace rewrite when cluster mode is active.

## Root cause

When `repl-namespace-enabled` is set to `yes`, the server rewrites namespace data into RocksDB on every startup. Each write to RocksDB increments the internal sequence number. When a slave restarts, this namespace rewrite bumps the slave's sequence number higher than the master expects. Incremental replication uses sequence numbers to determine where to resume, so the slave starts replicating from the wrong offset -- skipping over updates that occurred on the master during the slave's downtime.

The namespace rewrite mechanism is intended for standalone mode. In cluster mode, namespaces are not used, but the rewrite still runs if `repl-namespace-enabled` is enabled. Even outside cluster mode, the unconditional rewrite on startup causes the sequence number drift that breaks incremental replication.

## Fix description

The fix adds a guard to skip the namespace data rewrite into RocksDB when cluster mode is enabled. This prevents the spurious sequence number increment on startup, ensuring that the slave's replication offset remains consistent with the master after a restart.

Changes are in three files:
- `src/server/namespace.cc` — Skip namespace rewrite when cluster mode is enabled.
- `src/storage/redis_pubsub.cc` — Skip pubsub namespace rewrite when cluster mode is enabled.
- `src/storage/storage.cc` — Skip storage namespace rewrite when cluster mode is enabled.

Each change adds a 3-line guard that checks whether cluster mode is active and returns early if so.

## Key files
- `src/server/namespace.cc`
- `src/storage/redis_pubsub.cc`
- `src/storage/storage.cc`

## How to apply
```bash
git checkout 7e1b797920517edf9c798cd4b440789b524d7956
git submodule update --init --recursive
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## How to verify
Set up a master-slave pair with `repl-namespace-enabled yes`. Write a key, verify it replicates to the slave, then stop the slave. Write more keys on the master while the slave is down. Restart the slave and verify that all keys written during downtime are correctly replicated.
