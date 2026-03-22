# Solution: NATS #7718

## Fix
- **PR:** https://github.com/nats-io/nats-server/pull/7720
- **Commit:** `b72becc443073300e5599d06fa0cde1cd5518589`

## Root cause

When stream imports overlap (e.g., both `events.>` and `events.critical.>`), the subscription cleanup logic does not properly handle the case where a subscription matches multiple import paths. When an OrderedConsumer is destroyed, the cleanup code removes the subscription from one import path but leaves it registered under the overlapping import path.

This means each consumer create/destroy cycle leaks one subscription for each additional overlapping import path. With two overlapping imports, each cycle leaks one subscription.

## Fix description

The fix corrects the subscription cleanup logic to properly handle overlapping stream import scenarios:

- When unsubscribing, check all import paths that the subscription matches, not just the primary one.
- Remove the subscription from all matching import tracking structures.
- Ensure that the reference counting for shared subscriptions across overlapping imports is correct.

## How to apply
```bash
git checkout b72becc443073300e5599d06fa0cde1cd5518589
go build -o nats-server .
```

## How to verify
Run the consumer churn test (see verification.md). After 200 consumer create/destroy cycles, the subscription count should remain stable (within a small delta of the initial count).
