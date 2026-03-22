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

Use `iptables` to drop packets destined for the replica port, simulating a slow replica:
```bash
# Drop 90% of packets to the replica port (6667) to create significant replication lag
sudo iptables -A OUTPUT -p tcp --dport 6667 -m statistic --mode random --probability 0.9 -j DROP
```

**Note:** Do not use `tc qdisc add dev lo root netem ...` on the loopback interface — it throttles all loopback traffic including the benchmark client's connection to the master, making the test impractical. The `iptables` approach targets only the replica port.

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
sudo iptables -D OUTPUT -p tcp --dport 6667 -m statistic --mode random --probability 0.9 -j DROP 2>/dev/null
```
