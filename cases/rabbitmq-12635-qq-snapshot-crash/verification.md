# Verification: RabbitMQ #12635

The `gh_12635` test case from the fix PR is injected into `deps/rabbit/test/quorum_queue_SUITE.erl` and executed via Common Test against the buggy codebase.

## Test: gh_12635 (quorum queue snapshot crash)

```bash
make -C deps/rabbit ct-quorum_queue CASES=gh_12635
```

- **FAIL (bug present):** The quorum queue member on node 3 crashes after installing the Raft snapshot. The test detects a `DOWN` monitor message from the Ra server process and calls `ct:fail("unexpected DOWN")`. The CT output shows a failed test case with a `lists:zipwith` crash in the error logs.

- **PASS (bug fixed):** The quorum queue member on node 3 successfully installs the snapshot and does not crash. The `delivery_effect/3` function handles the stale log read gracefully by checking that the number of commands returned matches what was requested. If fewer commands are returned (stale read), it returns no effects instead of crashing.

## What the fix does

The fix in `deps/rabbit/src/rabbit_fifo.erl` makes two changes:

1. In `delivery_effect/3`: Adds a function clause guard `when length(Commands) < Num` that catches the case where the log returns fewer entries than requested. Instead of crashing in `lists:zipwith`, it logs a warning and returns an empty effect list.

2. In `reply_log_effect/5`: Adds a clause `fun ([]) -> []` to handle the case where the log returns no entries for a dequeue reply, returning an empty effect list instead of crashing.

## Combined verification

The `reproduce.sh` script injects the test, runs it, and reports:
- **FAIL:** The CT test fails (bug is present -- member crashes)
- **PASS:** The CT test passes (bug is fixed -- stale reads handled gracefully)
