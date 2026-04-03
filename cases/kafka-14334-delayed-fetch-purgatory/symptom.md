# Symptom

Consumers configured to fetch from follower replicas always wait the full `fetch.max.wait.ms` timeout before receiving data, even when new messages have already been replicated to the follower.

## Observable behavior

- A Kafka cluster is configured with `fetch.from.follower.enabled=true` and a rack-aware replica selector.
- A producer writes records to the leader, which replicates them to the follower.
- A consumer in the same rack as the follower sends a fetch request to the follower with `fetch.max.wait.ms` set (e.g., 500 ms).
- The consumer does NOT receive the newly replicated records until `fetch.max.wait.ms` elapses, even though the data is already present on the follower.

## Error messages

No explicit error is logged. The symptom is a latency spike: consumers observe that data is not available from followers until the fetch timeout expires, rather than being delivered promptly after replication.

## Impact

- Increased end-to-end latency for fetch-from-follower consumers.
- The benefit of fetching from a nearby follower (reduced cross-rack traffic, lower latency) is negated by the mandatory timeout wait.
