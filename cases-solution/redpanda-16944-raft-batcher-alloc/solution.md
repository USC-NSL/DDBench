# Solution: Redpanda #16944

## Fix
- **PR:** https://github.com/redpanda-data/redpanda/pull/17425
- **Commit:** `952b8c96298380b5986e4dfe71dba5616a2495b3`

## Root cause
The `raft::replicate_batcher` uses a `std::vector` to cache batches of records pending replication. Under high write throughput, this vector grows dynamically and, due to `std::vector`'s contiguous memory requirement, eventually needs a single large allocation when it doubles capacity. Once the vector reaches a capacity of 262144 bytes (256 KB), it exceeds Seastar's per-core allocator threshold for "oversized" allocations.

Seastar's memory model is designed around small, per-core allocations. Large contiguous allocations:
1. Are less efficient to allocate and free
2. Cause memory fragmentation on the per-core allocator
3. Can lead to allocation failures or latency spikes

## Fix description
Replace `std::vector` with `ss::chunked_fifo` (or `fragmented_vector` / `chunked_vector`) for the batches cache in `raft::replicate_batcher`. Unlike `std::vector`, a chunked vector stores data in fixed-size chunks (typically 128 KB or less), so it never requires a single contiguous allocation beyond the chunk size. This keeps all allocations within Seastar's efficient allocation range.

Key file: `src/v/raft/replicate_batcher.h` and/or `src/v/raft/replicate_batcher.cc`

The change is straightforward — replace the type declaration:
```cpp
// Before (buggy):
std::vector<item_ptr> _item_cache;

// After (fixed):
ss::chunked_fifo<item_ptr> _item_cache;
// or: fragmented_vector<item_ptr> _item_cache;
```

## How to apply
```bash
git checkout 952b8c96298380b5986e4dfe71dba5616a2495b3
git submodule update --init --recursive
# Build following setup.md instructions
```
