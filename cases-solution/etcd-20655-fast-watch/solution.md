# Solution: etcd #20655

## Fix
- **Reproduction PR:** https://github.com/etcd-io/etcd/pull/20654
- **Status:** Fix pending (as of issue report)

## Root cause
High-frequency watch creation creates a race condition in the watch subsystem. When multiple watches are created in rapid succession, there is a window where events can be committed to the store but not yet visible to newly created watches. The watch creation path does not properly synchronize with the event notification path, leading to dropped events.

## Fix description
Fix the race in the watch creation path to ensure that watches established at a given revision reliably receive all events from that revision onward. The fix needs to ensure atomicity between watch registration and event delivery initialization.

## Key areas
- Watch subsystem in `server/mvcc/watchable_store.go`
- Watch creation and event syncing logic

## How to verify
Apply the reproduction test from PR #20654 and confirm it passes after the fix.
