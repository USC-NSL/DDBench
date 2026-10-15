# Symptom

When a watcher's start revision falls below the compaction revision, the watcher should receive a compaction notification so the client knows it must re-establish the watch. Instead, the watcher silently loses all events and never receives the compaction notification.

## Observable behavior
- A client creates one or more watches on a key starting from a low revision (e.g., revision 1).
- Keys are written multiple times, then a compaction is performed at a revision above the watchers' start revisions.
- The watch channel buffer fills up (e.g., two compacted watchers compete for a single-slot buffer).
- One watcher's compaction response is delivered, but the other watcher's compaction response is dropped because the channel is full.
- The watcher that failed to receive the compaction notification never receives it later, even once the channel has room again.
- The watcher never catches up: it neither receives the compaction error nor the events it missed. From the client's perspective, the watch appears stalled with no indication of data loss.
