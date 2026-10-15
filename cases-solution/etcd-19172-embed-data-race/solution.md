# Solution: etcd #19172

- **Issue:** https://github.com/etcd-io/etcd/issues/19172
- **Fix commit:** [`43431bd6f83b60d13a29ef9df53d7f04fe63fcfd`](https://github.com/etcd-io/etcd/commit/43431bd6f83b60d13a29ef9df53d7f04fe63fcfd) — Mainline fix (PR #19221); release-3.5 backport: 3c04b6c7fc1d8a46f1f3e96794060c8d06526a33.
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/etcd-io/etcd/pull/19221 (main), https://github.com/etcd-io/etcd/pull/19258 (3.5 backport)
- **Commit:** `43431bd6f83b60d13a29ef9df53d7f04fe63fcfd` (main), `3c04b6c7fc1d8a46f1f3e96794060c8d06526a33` (3.5)

## Root cause
The bug was introduced by PR #19139, which moved `waitgroup.Add` calls into goroutines. This created a race condition where `e.wg.Add(1)` could be called after `e.wg.Wait()` was released. The `Etcd.Close()` goroutine writes to a shared field while `Etcd.errHandler()` reads it concurrently, with no synchronization.

## Fix description
Add proper synchronization around the shared field access between `Close()` and `errHandler()`. The fix ensures that the error handler goroutine and the close goroutine do not race on shared state by refactoring the concurrent control implementation.

## Key files
- `server/embed/etcd.go` — the `Close()` method and `errHandler()` method

## How to apply
```bash
git checkout 43431bd6f83b60d13a29ef9df53d7f04fe63fcfd
make build
```
