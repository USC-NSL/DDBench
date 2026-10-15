# Solution: RocksDB #10751

- **Issue:** https://github.com/facebook/rocksdb/issues/10751
- **Fix commit:** [`a45e6878f39cdc777c54e5d6749d53c1f70e2b52`](https://github.com/facebook/rocksdb/commit/a45e6878f39cdc777c54e5d6749d53c1f70e2b52)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **Issue:** https://github.com/facebook/rocksdb/issues/10751
- **Commit:** `a45e6878f39cdc777c54e5d6749d53c1f70e2b52`

## Root cause
When writes are stalled (due to write rate limiting, L0 file count exceeding `level0_stop_writes_trigger`, or memtable count limits), the writer threads block on a condition variable waiting for the stall to be released. The stall is normally released when compaction or flush reduces the L0 file count or memtable pressure.

During `DB::Close()`, the shutdown sequence stops background compaction and flush threads. However, it does not wake up the stalled writer threads. The result is a deadlock:
- `Close()` waits for everything to quiesce
- Stalled writers wait for the stall condition to be cleared
- Compaction/flush threads (which would normally clear the stall) are shut down

## Fix description
During the shutdown sequence in `DB::Close()`, explicitly wake up all stalled writers before waiting for them to finish. The writers, upon waking, should detect that the database is shutting down and return an appropriate error (e.g., `Status::ShutdownInProgress()`) instead of trying to proceed with the write.

The key changes are in `db/db_impl/db_impl.cc` (or `db_impl_write.cc`):

1. In the `Close()` / `CloseHelper()` method, set a shutdown flag
2. Signal the write stall condition variable to wake all blocked writers
3. In the write path, check the shutdown flag after waking from a stall and return early with an error

```cpp
// In Close():
shutting_down_.store(true);
// Wake up stalled writers
write_controller_.NotifyAll();  // or equivalent

// In the write stall wait loop:
if (shutting_down_.load()) {
    return Status::ShutdownInProgress();
}
```

## How to apply
```bash
git checkout a45e6878f39cdc777c54e5d6749d53c1f70e2b52
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```
