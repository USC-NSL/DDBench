# Solution: NATS #7852

- **Issue:** https://github.com/nats-io/nats-server/issues/7852
- **Fix commit:** [`66e9bbc7f8684dd1b31c54ef686924e0841f9846`](https://github.com/nats-io/nats-server/commit/66e9bbc7f8684dd1b31c54ef686924e0841f9846)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/nats-io/nats-server/pull/7856
- **Commit:** `66e9bbc7f8684dd1b31c54ef686924e0841f9846`

## Root cause
When a consumer has a single subject in its `FilterSubjects` field, the NATS server activates the subject filtering code path for every delivered message. This filtering path involves per-message subject matching overhead, even when the filter would match every message in the stream.

The problem is specifically with the single-subject case in `FilterSubjects` — it does not get the same optimization as a consumer with no filter. The filtering code path runs `subjectIsSubsetMatch()` or similar for every message, adding unnecessary CPU overhead.

## Fix description
Optimize the case where a single subject in `FilterSubjects` matches all subjects in the stream. When the filter effectively matches everything (e.g., `"stream.>"` on a stream with subjects `"stream.>"`), bypass the per-message filtering overhead entirely.

The fix detects this case during consumer creation/initialization and treats it as equivalent to having no filter, avoiding the unnecessary filtering code path during message delivery.

Key file: `server/consumer.go` (or the equivalent consumer delivery path in the NATS server).

## How to apply
```bash
git checkout 66e9bbc7f8684dd1b31c54ef686924e0841f9846
go build -o nats-server .
```
