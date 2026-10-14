# Solution: Kvrocks #3356

## Fix
- **PR:** https://github.com/apache/kvrocks/pull/3357
- **Commit:** `559a667bef223a07fea350a27168e91fe0a74601`

## Root cause

When a replica runs `PSYNC`, the master switches the replica's socket to blocking mode (`cmd_replication.cc`) and starts a `FeedSlaveThread`. In `FeedSlaveThread::loop()` (`src/cluster/replication.cc`), the thread packs WAL batches and sends them with `util::SockSend()`. For a plain socket, this is `WriteImpl<write>`: a loop over a blocking `write()` with no timeout.

If the replica stops reading while its TCP connection stays alive (congestion, a stalled replica process), the kernel send buffer fills and `write()` blocks forever. Nothing ever unblocks it:
- `checkLivenessIfNeed()` only runs between sends, so it can't run while the thread is stuck inside one.
- `Stop()` / `CLIENT KILL` only set a flag that the blocked thread never checks.
- TCP keepalive and retransmission timeouts don't fire, because the peer's kernel keeps answering zero-window probes.

So the master keeps the replica listed as connected indefinitely, and logs nothing. Meanwhile client writes continue and WAL files rotate and are pruned past the replica's `next_repl_seq`. When the thread eventually resumes, `GetWALIter` finds a gap and logs "WAL iterator is discrete, some seq might be lost". The replica's psync then fails with "sequence out of range", which forces a full resync.

The case title's "WAL exhaustion" means the replica's WAL position gets pruned away, not that the disk fills up.

## Fix description

1. **Send timeout:** new `util::SockSendWithTimeout()` (`io_util.cc`) waits with `poll()` (`AeWait`) for the socket to become writable, up to `replication-send-timeout-ms` (default 30000). The feed thread uses it instead of `SockSend`. On timeout the thread logs an error and calls `Stop()`, so the stuck replica is detached while its position is still in the WAL.
2. **Lag check:** at the top of each loop iteration, the replica is disconnected if `LatestSeqNumber() - curr_seq > max-replication-lag`. This check is off by default (`0`).
3. **Reconnect backoff:** on the replica side, reconnects use exponential backoff (1 s, 2 s, 4 s, up to 60 s). The counter resets after a successful psync or fullsync.

## How to apply
```bash
git checkout 559a667bef223a07fea350a27168e91fe0a74601
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## How to verify
Run `reproduce.sh`. It freezes the replica with `SIGSTOP`, fills the replication socket with 64 MB of writes, and watches the master for 90 s. On the fixed build, the master detaches the replica after about 30 s. The log shows `Write error while sending batch to slave ...: send timeout ...`. After `SIGCONT`, the replica reconnects and catches up, so the script reports PASS.
