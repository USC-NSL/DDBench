# Symptom: Seastar #2202

When a memory buffer is allocated on one shard (CPU core) and then `realloc`'d to a smaller size on a different shard, Seastar's memory allocator crashes with an assertion failure:

```
Assertion `object_cpu_id(ptr) == cpu_id' failed.
```

This occurs because the realloc shrink path assumes the object belongs to the current shard and asserts this, but cross-shard realloc is a valid operation that should be handled gracefully (similar to how cross-shard `free` is already handled).

The crash is deterministic and occurs every time a cross-shard realloc-to-smaller-size is performed.
