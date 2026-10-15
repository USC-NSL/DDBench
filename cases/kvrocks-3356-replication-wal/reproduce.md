# Reproduce: Kvrocks #3356

## Prerequisites
Run inside `./bench.sh shell kvrocks-3356-replication-wal`, from `/workspace/src`; `./bench.sh setup` has built Kvrocks at `build/kvrocks` (Debug). `redis-cli` and `python3` are in the image. No root, iptables, or `tc` is needed.

## Step 1: Start master and replica

```bash
mkdir -p /tmp/kv-master /tmp/kv-replica
cat > /tmp/master.conf <<EOF
bind 127.0.0.1
port 13356
dir /tmp/kv-master
EOF
cat > /tmp/replica.conf <<EOF
bind 127.0.0.1
port 13357
dir /tmp/kv-replica
slaveof 127.0.0.1 13356
EOF
./build/kvrocks -c /tmp/master.conf &
./build/kvrocks -c /tmp/replica.conf & REPLICA_PID=$!
sleep 3
redis-cli -p 13356 INFO replication   # connected_slaves:1, slave0:...
```

## Step 2: Make the replica stop consuming, keeping its connection open

```bash
kill -STOP $REPLICA_PID
```

The replica process no longer reads from its socket. Its kernel keeps the TCP connection alive and advertises a zero receive window. To the master, this looks the same as a replica stuck behind a congested network.

## Step 3: Write more data than the socket buffers can hold

```bash
python3 -c '
import sys
v = b"x" * 262144
for i in range(256):
    k = b"fill:%d" % i
    sys.stdout.buffer.write(b"*3\r\n$3\r\nSET\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n" % (len(k), k, len(v), v))
' | redis-cli -p 13356 --pipe
```

## Step 4: Observe the master

```bash
watch -n 5 'redis-cli -p 13356 INFO replication; grep ":342C " /proc/net/tcp'
```

`342C` is port 13356 in hex. The `tx_queue` column of the master→replica connection shows the send queue.

## Expected result (bug present)
- The replica is still listed as attached after 90 s, and stays attached for as long as the replica is stalled.
- The master's send queue on the replication connection stays at about 2.4 MB and does not change.
- Nothing about the replica appears in the master log.

## Expected result (bug fixed)
- The master detaches the stalled replica within a bounded time (`slave0` disappears from `INFO replication`).
- After `kill -CONT $REPLICA_PID`, the replica reconnects and catches up with new writes.

## Cleanup
```bash
kill -CONT $REPLICA_PID; pkill -9 -f 'kvrocks -c /tmp/(master|replica).conf'
```

## Oracle verdict

`./bench.sh reproduce kvrocks-3356-replication-wal` rebuilds the worktree and runs the oracle (`reproduce.sh`). It follows the steps above: it waits until the replica is in sync, freezes it with `SIGSTOP`, writes 64 MB to the master, confirms that the master's send queue on the replication connection is non-empty, and then watches `INFO replication` for 90 s under a light write load.

- **FAIL** (exit 1): the master still lists the stalled replica after 90 s, or the master dies during the stall, or it detaches the replica but replication does not recover within 90 s after `SIGCONT`. A worktree that does not build, a master that does not start, or a replica that never syncs before the stall is also FAIL.
- **PASS** (exit 0): the master detaches the stalled replica within 90 s, and after `SIGCONT` the replica reconnects (`master_link_status:up`) and serves a key written after the stall.
- **ERROR** (exit 2): the stall could not be established (no queued data on the replication connection and the replica still attached), or the case is not set up.
