# Solution: NATS Server #7726

- **Issue:** https://github.com/nats-io/nats-server/issues/7726
- **Fix commit:** [`74c12317902f02e7cb8748364fb383852c99e4ce`](https://github.com/nats-io/nats-server/commit/74c12317902f02e7cb8748364fb383852c99e4ce)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/nats-io/nats-server/pull/7745 ("Fix subject intersection bug due to early return")
- **Commit:** `74c12317902f02e7cb8748364fb383852c99e4ce` (merge of PR #7745; first parent `46189422fb0f76abcdd3a2eff568fb3e018f788d` is the case's buggy commit)
- **Gold patch:** `gold.patch` in this directory (source only: `server/gsl/gsl.go`)

## Case history (why the buggy commit is `74c12317~1`)
Issue #7726 was opened as a follow-up to #7713. Its reporter showed that PR #7725
(`6aded805`, which fixed the simple #7713 reproduction) still failed for their
production filter set. PR #7725 was then reverted (#7729), and PR #7741
(`7a7ff0dc`, "Subject tree-driven intersection") replaced the intersection
algorithm and closed #7726. The reporter confirmed the bug still reproduced with
that change. PR #7745 (`74c12317`) fixed it, and the reporter confirmed that fix.

Earlier versions of this case used `6aded805~1` as the buggy commit and the #7713
`PWCDoesntHideLiteral` test as the oracle, with `6aded805` (later reverted
upstream) as the gold fix. That reproduced #7713, not #7726. The case now pins the
state right before the confirmed #7726 fix, and its oracle reproduces the #7726
report.

## Fix locus
- **Component:** generic sublist (`server/gsl/gsl.go`), `hasInterestStartingIn()`, used by the subject-tree-driven intersection (`stree.IntersectGSL`) when a consumer has several filter subjects.

## Root cause
`hasInterestStartingIn()` answers "is there any filter that could match a subject
starting with these tokens?" while the subject tree is walked. At a level that has
a partial wildcard (`*`) node, it returned the result of descending only the
wildcard branch. It never looked at the literal node for the same token. If the
tokens after the wildcard differed from the subject's next tokens, it returned
`false`, even though a literal filter at the same level would match. The subject
tree walk was then pruned, so messages on the literal filter subject were never
found for the consumer.

Example: with filters `events.*.datastore.batch.access.modified` and
`events.main.datastore.result.created`, checking the prefix
`events.main.datastore.result` descends only `*` → `datastore` → `batch` and fails.
The literal path `main` → `datastore` → `result` is never checked.

## Fix description
Check both the partial-wildcard branch and the literal branch, and return true if
either one has interest, instead of returning early from the wildcard branch.

## How to apply
```bash
git apply cases-solution/nats-7726-mixed-filter/gold.patch   # in the worktree
go build -o nats-server .
```

## How to verify
`./bench.sh reproduce nats-7726-mixed-filter` must print `PASS:` and exit 0.
