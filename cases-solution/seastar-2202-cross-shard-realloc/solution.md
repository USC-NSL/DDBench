# Solution: Seastar #2202

## Fix
- **Issue:** https://github.com/scylladb/seastar/issues/2202

## Root cause

In Seastar's memory allocator (`src/core/memory.cc`), the `realloc` implementation has a fast path for shrinking allocations that asserts the object belongs to the current CPU/shard:

```cpp
assert(object_cpu_id(ptr) == cpu_id);
```

However, cross-shard realloc is a valid operation. Seastar already handles cross-shard `free()` by sending the deallocation to the owning shard. But the realloc shrink path does not check for cross-shard ownership before asserting.

When shard 1 tries to realloc-shrink a buffer owned by shard 0, the assertion fires and the process aborts.

## Fix description

The fix handles cross-shard realloc shrink the same way cross-shard frees are handled:

In `src/core/memory.cc`, in the `realloc` function, before the shrink fast-path, check if the object belongs to a different shard. If so, perform a new allocation on the current shard, copy the data, and free the old buffer via cross-shard free:

```cpp
void* realloc(void* ptr, size_t new_size) {
    if (!ptr) return malloc(new_size);
    if (new_size == 0) { free(ptr); return nullptr; }

    auto obj_cpu = object_cpu_id(ptr);
    if (obj_cpu != this_shard_id()) {
        // Cross-shard realloc: allocate new, copy, free old
        void* new_ptr = malloc(new_size);
        if (new_ptr) {
            size_t old_size = object_size(ptr);
            memcpy(new_ptr, ptr, std::min(old_size, new_size));
            free(ptr);  // cross-shard free handles sending to correct shard
        }
        return new_ptr;
    }

    // Original logic for same-shard realloc...
}
```

## How to verify
After applying the fix, rebuild and run the cross-shard realloc test:
```bash
./test_cross_shard_realloc --smp 2
# Should complete without assertion failure
```
