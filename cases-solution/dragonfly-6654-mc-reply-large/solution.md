# Solution: Dragonfly #6654

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6657
- **Commit:** `ff4ef508985cb91a7fdf418682af1534c24acf83`

## Root cause
In the memcached reply builder, the meta get response for large values computes an `expected_buffer_cap` that can exceed `kMaxBufferSize` (8192 bytes). For a value of ~8000 bytes, the header metadata plus the value payload pushes the buffer requirement to ~8242 bytes, exceeding the limit and triggering a fatal assertion.

## Fix description
Use `WriteRef` for large values instead of buffering them entirely in the reply builder's internal buffer. This avoids the buffer size limit by writing the value through a reference-based path that does not require the entire value to fit in the fixed-size buffer.

## How to apply
```bash
git checkout ff4ef508985cb91a7fdf418682af1534c24acf83
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
