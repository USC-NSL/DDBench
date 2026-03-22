# Reproduce: Kvrocks #3356

## Prerequisites
A Kvrocks master-replica setup (see setup.md).

## Step 1: Start master and replica

```bash
./build/kvrocks -c master.conf &
./build/kvrocks -c replica.conf &
sleep 3
```

Verify replication is working:
```bash
redis-cli -p 6666 INFO replication
# Should show connected_slaves:1
```

## Step 2: Throttle replica network

Use `tc` (traffic control) to simulate a slow replica:
```bash
# On Linux, throttle the replica's incoming bandwidth
sudo tc qdisc add dev lo root netem delay 100ms rate 100kbit
```

Or alternatively, use `iptables` to drop some packets to the replica:
```bash
sudo iptables -A OUTPUT -p tcp --dport 6667 -m statistic --mode random --probability 0.5 -j DROP
```

## Step 3: Generate high write load on master

```bash
redis-benchmark -p 6666 -t set -n 1000000 -r 1000000 -d 256 -c 50 -P 32
```

## Step 4: Monitor WAL growth

```bash
watch -n 2 'du -sh /tmp/kvrocks-master/'
```

## Step 5: Check replication status

```bash
redis-cli -p 6666 INFO replication
# Check replication lag
```

## Expected result (bug present)
- WAL directory grows continuously without bound (several GB under sustained load).
- The replication feed thread blocks on the slow consumer.
- Eventually, replication lag exceeds WAL retention and a forced fullsync occurs.
- Master disk usage grows dangerously.

## Cleanup
```bash
sudo tc qdisc del dev lo root 2>/dev/null
sudo iptables -D OUTPUT -p tcp --dport 6667 -m statistic --mode random --probability 0.5 -j DROP 2>/dev/null
```
