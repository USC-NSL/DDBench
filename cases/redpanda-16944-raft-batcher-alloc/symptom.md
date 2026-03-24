# Symptom

Under high write throughput, Redpanda logs oversized allocation warnings from the raft replicate batcher:

```
WARNING: oversized allocation: 262144 bytes, please report: raft::replicate_batcher::flush
```

This warning indicates that the Seastar allocator detected a contiguous memory allocation of 262144 bytes (256 KB), which is above the threshold for efficient allocation in Seastar's per-core memory model.

The issue manifests as:
1. Warning messages flooding the logs during high-throughput produce workloads
2. Potential memory fragmentation over time
3. Possible latency spikes due to large contiguous allocation pressure

The oversized allocation comes from the internal batches cache in `raft::replicate_batcher`, which uses a `std::vector`. As the vector grows during high-throughput replication, it doubles its capacity, eventually requiring a single contiguous allocation that exceeds Seastar's recommended maximum.
