# Reproduce: Kvrocks #3356

## Prerequisites
A built `kvrocks` binary (see setup.md), `redis-cli`, and `python3`. No root, iptables, or `tc` is needed.

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
