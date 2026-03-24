# Symptom

During topology changes that involve streaming (node join, decommission, or rebuild), ScyllaDB crashes with a use-after-free (UAF) in `streaming_task_impl::run`.

When built with AddressSanitizer (ASAN), the error report shows:
```
ERROR: AddressSanitizer: heap-use-after-free
READ of size X at 0x...
  #0 streaming_task_impl::run()
  #1 coroutine::lambda...
  ...
freed by thread T0 here:
  ...
```

Without ASAN, the crash may manifest as:
- Segmentation fault during streaming
- Corrupted data in streaming responses
- Intermittent crashes during node operations

The issue involves a `coroutine::lambda` that keeps a pointer to a lambda object, but the lambda's lifetime ends before the streaming task actually executes the coroutine. By the time the streaming task runs, the pointer is dangling.
