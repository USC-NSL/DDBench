# Symptom

Under high write load, the replication feed thread on the master blocks indefinitely when a replica is slow to consume replication data. This causes:

1. The WAL (Write-Ahead Log) grows unbounded because the feed thread is blocked and cannot advance the consumer offset.
2. Disk usage increases rapidly as WAL files accumulate.
3. Eventually, the WAL grows so large that the master runs out of disk space or the replication lag becomes so large that a full resync (fullsync) is forced.
4. The forced fullsync under already-stressed conditions can cause further instability.

The core issue is that the replication feed thread has no timeout or backpressure mechanism when writing to a slow consumer, so a single slow replica can cause unbounded WAL growth on the master.
