# Solution: Kvrocks #3339

## Fix
- **PR:** https://github.com/apache/kvrocks/pull/3337
- **Commit:** `25216331bce6f9e97b945aad1cbb04e2db261287`

## Root cause

In the `OnWrite` callback for XREAD/XREADGROUP, when the blocking command finds no data available, it sends an empty response but fails to `return` afterward. Execution falls through to the code that handles the case where data becomes available, which sends a second response.

The control flow looks like:
```
OnWrite() {
    result = try_read_from_stream();
    if (result.empty()) {
        send_empty_response();  // First response sent
        // BUG: missing return here!
    }
    // Falls through to:
    send_data_response(result);  // Second response sent
}
```

Under concurrent load, a race condition makes this happen:
1. XREADGROUP BLOCK is called, no data available, the command blocks.
2. XADD adds data, wakes the blocked command.
3. OnWrite is called, but between checking and sending, the data state changes.
4. The empty check sends one response, then the data path sends another.

## Fix description

Add a missing `return` statement in the `OnWrite` callback after sending the empty response:

```cpp
if (result.empty()) {
    send_empty_response();
    return;  // <-- This was missing
}
```

This ensures that only one response is sent per command invocation.

## How to apply
```bash
git checkout 25216331bce6f9e97b945aad1cbb04e2db261287
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## How to verify
Run concurrent XREADGROUP BLOCK consumers with concurrent XADD producers. Verify no protocol errors or double responses occur.
