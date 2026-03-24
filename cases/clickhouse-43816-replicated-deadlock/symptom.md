# Symptom

On a ReplicatedMergeTree cluster under sustained write load, background merges start but never complete. The system hangs with the following observable symptoms:

1. `system.merges` shows merges with `progress = 0` that are stuck for more than 10 minutes.
2. `system.replicas` shows an increasing number of parts that are not being merged.
3. Thread dumps show threads stuck in `pthread_cond_wait` inside `ReplicatedMergeTreeQueue::setActualPartName`.
4. The background merge pool becomes fully occupied by stuck merges, preventing any new merges from starting.
5. Eventually, the number of parts grows unbounded and queries slow down or fail with "too many parts" errors.

The deadlock is between the `ReplicatedMergeTreeQueue` lock and the `MergeTreeBackgroundExecutor` internal synchronization. Neither side can make progress.
