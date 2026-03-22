# Solution: Redpanda #25769

## Fix
- **Issue:** https://github.com/redpanda-data/redpanda/issues/25769
- **Fix PR:** https://github.com/redpanda-data/redpanda/pull/25932
- **Fix commit:** `18b0c24d7b306add4a1390fc2c56a5de5420f567`

## Root cause

The `batch_timequery()` function, which handles the `ListOffsets` API's timestamp-based lookup, does not decompress compressed record batches before searching for records by timestamp. When a batch is compressed, the individual record timestamps are only accessible after decompression. Without decompression, the function can only see the batch-level metadata (first/last timestamp), and cannot locate the specific record within the batch that matches the target timestamp.

As a result, for compressed batches, the function returns the batch's base offset instead of the offset of the specific record within the batch that first meets or exceeds the requested timestamp.

## Fix description

The fix modifies `batch_timequery()` to decompress the batch before iterating over individual records to find the matching timestamp. The decompression is only performed when the batch's timestamp range indicates it could contain the target timestamp (i.e., the batch's max timestamp >= target timestamp), avoiding unnecessary decompression of batches that can be skipped entirely.

## Files changed

- **`src/v/storage/log_reader.cc`** (or the file containing `batch_timequery`) — Added decompression step before iterating over records in the batch. The function now:
  1. Checks if the batch's timestamp range could contain the target timestamp.
  2. If the batch is compressed, decompresses it.
  3. Iterates over individual records to find the first one with timestamp >= target.
  4. Returns the correct offset for that record.

## How to apply the fix
```bash
cd redpanda
git checkout 18b0c24d7b306add4a1390fc2c56a5de5420f567
git submodule update --init --recursive
mkdir build && cd build
cmake .. -GNinja -DCMAKE_BUILD_TYPE=Release
ninja redpanda
```

Or use a fixed Docker image:
```bash
docker pull redpandadata/redpanda:v24.3.8  # or later
```
