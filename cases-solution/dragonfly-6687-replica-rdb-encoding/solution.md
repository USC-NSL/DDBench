# Solution: Dragonfly #6687

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6807
- **Commit:** `8347cd80192a7be967a3983a6a55a10525915015`

## Root cause

When tiered storage is enabled, some entries in the DashTable are in a "delayed" state, meaning their actual data is stored on disk rather than in memory. During replication, the `SerializeBucket` function iterates over DashTable entries and serializes them into the RDB stream sent to the replica.

However, `SerializeBucket` does not properly handle delayed (tiered) entries. Instead of fetching the actual data from disk before serializing, it serializes the internal delayed marker, which results in an invalid RDB encoding byte (62). The replica's RDB parser does not recognize this encoding and rejects the stream.

## Fix description

The fix ensures that `SerializeBucket` properly handles delayed entries by fetching their actual data from tiered storage before serialization:

- When iterating DashTable entries for serialization, check if an entry is a delayed/tiered entry.
- If so, fetch the actual value from the tiered storage backend before writing it to the RDB stream.
- This ensures the replica receives valid RDB-encoded data regardless of whether the master has tiered storage enabled.

## How to apply
```bash
git checkout 8347cd80192a7be967a3983a6a55a10525915015
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Release
```

## How to verify
Start master with tiered storage, load data, start replica, initiate `REPLICAOF`. Verify that `INFO replication` shows `master_link_status:up` on the replica.
