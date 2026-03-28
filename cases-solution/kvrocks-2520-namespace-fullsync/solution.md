# Solution: Kvrocks #2520

## Fix
- **Issue:** https://github.com/apache/kvrocks/issues/2520
- **PR:** https://github.com/apache/kvrocks/pull/2527
- **Commit:** `a29df097dd23c36a749e5c616f4d1cae1051e853`

## Fix locus
- **Component:** Replication / full sync handler, namespace manager
- **Files:** `src/cluster/replication.cc`, `src/server/namespace.cc`, `src/server/namespace.h`

## Root cause

When a replica completes a full sync (receiving the entire RocksDB snapshot from the master), the full sync handler in `src/cluster/replication.cc` swaps in the new database but does not reload the namespace metadata from the freshly received storage. The namespace entries are physically present in RocksDB (they were part of the snapshot), but the server's in-memory namespace map still reflects the old state from before the sync. As a result, only the default namespace is visible until the server is restarted, which triggers a fresh load from storage.

## Diagnosis chain

1. Observe that `NAMESPACE GET *` on the slave returns only the default namespace after full sync.
2. Restart the slave process (without any data changes) and observe that all namespaces appear.
3. This indicates the data is in storage but not in the in-memory state.
4. Trace the full sync completion path in `src/cluster/replication.cc` — after the DB swap, no call is made to reload namespaces from the new storage.
5. Compare with the server startup path, which does load namespaces from storage into the in-memory map.

## Fix description

The fix adds a call to `Namespace::LoadAndRewrite()` in the full sync handler in `src/cluster/replication.cc` after the database swap completes. This reloads the namespace metadata from the newly received RocksDB snapshot into the in-memory map. Additionally, `src/server/namespace.cc` and `src/server/namespace.h` are updated to expose and adjust the reload method so it can be called from the replication handler.

## Key files
- `src/cluster/replication.cc` (+7, -0) — Add namespace reload after full DB swap
- `src/server/namespace.cc` (+2, -1) — Adjust reload method
- `src/server/namespace.h` (+1, -3) — Expose reload method for external callers

## How to apply
```bash
git checkout a29df097dd23c36a749e5c616f4d1cae1051e853
git submodule update --init --recursive
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## How to verify
Start a master with multiple namespaces, start a slave, execute `SLAVEOF`, wait for full sync to complete, and run `NAMESPACE GET *` on the slave. All namespaces should be visible without a restart.
