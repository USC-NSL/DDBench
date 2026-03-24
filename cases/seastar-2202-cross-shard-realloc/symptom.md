# Symptom

When a memory buffer is allocated on one shard (CPU core) and then `realloc`'d to a smaller size on a different shard, Seastar's memory allocator crashes with an assertion failure:

```
Assertion `object_cpu_id(ptr) == cpu_id' failed.
```

## Observable behavior
- The crash is deterministic and occurs every time a cross-shard realloc to a smaller size is performed.
