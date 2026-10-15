# Reproduce: Kvrocks #3315

## Step 1: Start Kvrocks
```bash
./build/kvrocks -p 6666 --dir /tmp/kvrocks_data
```

## Step 2: Send the crashing command
```bash
redis-cli -p 6666 ZDIFF 0 a
```

## Expected result (bug present)
The kvrocks process crashes immediately.

## Oracle verdict

`./bench.sh reproduce kvrocks-3315-zdiff-crash` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `ZDIFF 0 a` is sent on a raw connection, Kvrocks exits (crashes), stops answering `PING`, closes the connection without a reply, or sends no reply within 10 s. A worktree that does not build, or Kvrocks that does not answer `PING` within 60 s of starting, is also FAIL.
- **PASS** (exit 0): Kvrocks sends a reply to `ZDIFF 0 a` (its content is not checked) and still answers `PING` afterwards.
- **ERROR** (exit 2): `REBUILD.sh` or the built `build/kvrocks` binary is missing (the case is not set up).
