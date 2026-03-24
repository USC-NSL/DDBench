# Symptom

Under high write load with a slow replica, the master's WAL (Write-Ahead Log) grows without bound, eventually exhausting disk space.

## Observable behavior
- WAL files accumulate on the master and are never cleaned up while the slow replica is connected.
- Disk usage increases rapidly during sustained writes.
- Eventually the master runs out of disk space or forces a full resync.
