# Test Output

Obtained by running `timeout 60 ./test_stall_shutdown` against the buggy build. The test program opens a RocksDB instance with aggressive write stall settings (rate limiter at 1024 bytes/sec, small write buffers), writes enough data to trigger stalling, then calls `DB::Close()`.

## Output

```
Opening database with stall-inducing settings...
Writing data to trigger stall condition...
Writes stalled. Calling Close()...

[process killed by timeout after 60 seconds — Close() never returned]
```
