# Solution: NATS Server #7817

- **Issue:** https://github.com/nats-io/nats-server/issues/7817
- **Fix commit:** [`a07f134d51a727fa051a042233ce00a8c18374f9`](https://github.com/nats-io/nats-server/commit/a07f134d51a727fa051a042233ce00a8c18374f9) — Fix landed on main (PR #7845); the buggy revision is the v2.12.3 release. Release-branch backport: 45d208915d27ca352fc2c1b70f415b1b98f1c3e3 (v2.12.5).
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/nats-io/nats-server/pull/7845
- **Commit:** `a07f134d51a727fa051a042233ce00a8c18374f9`

## Root cause
In `mset.checkInterestState`, once messages are no longer pending and are only in the redelivered state below the ack floor, `shouldRemove` would be set due to `mset.directs <= 0`. But `mset.noInterest(seq, o)` skipped the calling consumer, so it did not account for messages that had reached max deliveries and still needed to be retained.

The result was that messages reaching max-deliver were incorrectly considered as having no interest and removed from the WorkQueue stream.

## Fix description
Always call `mset.noInterest(seq, nil)` (without passing the consumer) to ensure there are no consumers left with interest, including messages left as max deliveries. This ensures that messages that reached max-deliver are preserved in the stream rather than being prematurely removed.

## How to apply
```bash
git checkout a07f134d51a727fa051a042233ce00a8c18374f9
go build -o nats-server .
```
