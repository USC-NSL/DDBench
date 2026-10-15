# Solution: NATS Server #7760

- **Issue:** https://github.com/nats-io/nats-server/issues/7760
- **Fix commit:** [`d345774fdb1c3e4e49297a7f9ca1da0a06065dab`](https://github.com/nats-io/nats-server/commit/d345774fdb1c3e4e49297a7f9ca1da0a06065dab) — Fix landed on main (PR #7773); the buggy revision is the v2.12.3 release. Release-branch backport: e2dacf3f086594171524628e6e1db27eafd7800c (v2.12.4).
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/nats-io/nats-server/pull/7773
- **Commit:** `d345774fdb1c3e4e49297a7f9ca1da0a06065dab`

## Root cause
An interest-based replicated stream could desync after a consumer filter update. When the consumer's filter subjects were edited, the internal sublist was cleared and only updated on the server that was the consumer leader. The stream on the consumer leader would persist the messages matching the new filter, but follower replicas would not.

After a leader step-down, the new leader had a stale (empty) sublist for the consumer, so it could not match any messages — resulting in timeouts.

## Fix description
PR #7773 fixes the interest stream state replication during leader transitions. It ensures the sublist is properly replicated to all nodes when consumer filters are updated, so that after a step-down the new leader has the correct filter state.

## How to apply
```bash
git checkout d345774fdb1c3e4e49297a7f9ca1da0a06065dab
go build -o nats-server .
```
