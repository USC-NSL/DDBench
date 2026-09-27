# Test Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 2 --dbfilename=""` and sending a pipeline containing `SET mykey myval`, `PING`, and `BLPOP nolist 5` via `printf "SET mykey myval\r\nPING\r\nBLPOP nolist 5\r\n" | redis-cli -p 16379 --pipe-timeout 10` against the buggy build.

## Output

```
=== Test 1: Pipeline with blocking command ===
OK
PONG

Elapsed: 5s
FAIL: Pipeline replies delayed 5s by BLPOP
```

