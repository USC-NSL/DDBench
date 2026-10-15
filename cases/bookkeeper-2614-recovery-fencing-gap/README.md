# BookKeeper #2614: Recovery Reads Missing Fencing Flag Allows Data Loss

| Field | Value |
|-------|-------|
| Project | [Apache BookKeeper](https://github.com/apache/bookkeeper) |
| Issue | [#2614](https://github.com/apache/bookkeeper/issues/2614) |
| Fix PR | [#2616](https://github.com/apache/bookkeeper/pull/2616) |
| Language | Java |
| Category | Protocol correctness (missing fencing flag in recovery reads) |

## Bug Summary

BookKeeper ledger recovery consists of three phases: (1) fencing via LAC reads, (2) recovery reads and write-back, (3) ledger close. Phase 2 begins once a write quorum of bookies has responded to the fencing LAC reads — but if one bookie's fencing request is lost or delayed, that bookie can still accept writes from the original writer.

The bug: Phase 2 recovery reads (in `PendingReadOp`) do not carry the fencing flag. A bookie that answers a recovery read without being explicitly fenced by the LAC read remains unfenced. If the original writer reaches this unfenced bookie last (as part of its ack quorum), the write succeeds after the recovering writer has already seen "empty" state from the fencing phase. The recovering writer then closes the ledger as empty, silently truncating the committed entry.

The fix adds `FLAG_DO_FENCING` to recovery reads, so that any bookie serving a recovery read is fenced by the act of reading — regardless of whether the LAC fence request was delivered.

Discovered through TLA+ formal verification of the BookKeeper replication protocol.

## Quick Start

```bash
# from the repository root
./bench.sh setup bookkeeper-2614-recovery-fencing-gap        # build image + case repository, warm caches
./bench.sh reproduce bookkeeper-2614-recovery-fencing-gap    # FAIL (exit 1) while the bug is present
./bench.sh shell bookkeeper-2614-recovery-fencing-gap        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/bookkeeper` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The test `testFirstWriterCannotCommitWriteAfter2ndWriterCloses` fails: w1's write succeeds even after w2 closes the ledger, demonstrating that a committed entry can be silently truncated.

**When the bug is fixed (PASS):**
Recovery reads fence the bookies they contact. w1's write to the already-read bookie gets rejected with `BKLedgerFencedException`.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable data loss behavior
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
