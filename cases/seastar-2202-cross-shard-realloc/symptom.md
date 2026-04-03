# Symptom

When a memory buffer is allocated on one shard (CPU core) and then `realloc`'d on a different shard, Seastar crashes with an assertion failure:

```
Assertion failed: memory object does not belong to the current CPU shard.
```

## Observable behavior
- The crash is deterministic and occurs every time a cross-shard `realloc` is performed.
