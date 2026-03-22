# Solution: RocksDB #13652

## Fix
- **Issue:** https://github.com/facebook/rocksdb/issues/13652
- **Commit:** `25d8a6b0b5ccde1b7d26920a264ebc7f810ee1b5`

## Root cause
`Checkpoint::ExportColumnFamily` has a race condition with concurrent writes. The export operation collects the list of SST files belonging to the column family, but it does not ensure that data currently in the memtable is included. There is a window between when the export decides which data to include and when it actually captures that data, during which new writes can be committed to the memtable.

Specifically:
1. Export starts and takes a snapshot of the current SST files
2. Meanwhile, writes are committed to the memtable
3. The export does not flush the memtable or otherwise ensure these writes are captured
4. The exported data only contains what was in SST files, missing memtable data

Even without concurrent writes, data written after the last flush but before the export call may be missing if the export does not force a flush.

## Fix description
Ensure that memtable data is flushed to SST files before (or as part of) the export operation. The fix adds a flush of the column family's memtable before collecting the SST file list for export. This guarantees that all committed data at the time of the export call is materialized in SST files and included in the export.

The change is in `utilities/checkpoint/checkpoint_impl.cc`:
```cpp
// Before export, flush the column family to ensure memtable data is on disk
Status s = db_->Flush(FlushOptions(), column_family);
if (!s.ok()) return s;
// Then proceed with collecting SST files for export
```

## How to apply
```bash
git checkout 25d8a6b0b5ccde1b7d26920a264ebc7f810ee1b5
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```
