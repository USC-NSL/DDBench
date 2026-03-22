# Symptom: hashicorp/raft #291

When a follower node in a Raft cluster is down or unreachable, repeatedly calling `VerifyLeader()` on the leader causes unbounded memory growth. The leader process's memory usage grows continuously (e.g., from 50MB to 278MB+ over minutes) and eventually leads to OOM (Out of Memory) kill.

The memory leak is proportional to the number of `VerifyLeader()` calls made while the follower is unreachable. Each call leaks a small amount of memory that is never reclaimed.

This is particularly dangerous because `VerifyLeader()` is commonly called by health checks and monitoring systems at regular intervals, making this a realistic production failure mode.
