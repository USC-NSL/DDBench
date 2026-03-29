# Solution: BookKeeper #2614

## Fix

- **PR:** https://github.com/apache/bookkeeper/pull/2616
- **Commit:** `017307bc67431a7616861ad09927c4e3327633d1`

## Fix locus

- **Component:** Recovery read operation (`bookkeeper-server/.../client/PendingReadOp.java`)
- **Files:**
  - `bookkeeper-server/src/main/java/org/apache/bookkeeper/client/PendingReadOp.java` (+8/-3) — in `sendReadTo()`, adds `BookieProtocol.FLAG_DO_FENCING` to the flags for recovery reads (changes `FLAG_HIGH_PRIORITY` → `FLAG_HIGH_PRIORITY | FLAG_DO_FENCING`)
  - `bookkeeper-server/src/test/java/org/apache/bookkeeper/client/LedgerRecovery2Test.java` (+227/-7) — adds `testFirstWriterCannotCommitWriteAfter2ndWriterCloses` test
  - `bookkeeper-server/src/test/java/org/apache/bookkeeper/proto/MockBookies.java` (+131/-0) — new shared mock bookie state for two-writer tests
  - `bookkeeper-server/src/test/java/org/apache/bookkeeper/proto/MockLedgerData.java` (+64/-0) — new per-ledger data class with fencing support
  - `bookkeeper-server/src/test/java/org/apache/bookkeeper/proto/MockBookieClient.java` (+69/-94) — adds fencing enforcement, pre-read/write hooks for timing control
  - `bookkeeper-server/src/test/java/org/apache/bookkeeper/client/MockClientContext.java` (+18/-12) — adds `create(MockBookies)` factory method for shared-state two-writer tests

## Root cause

`PendingReadOp.sendReadTo()` computed read flags as:

```java
int flags = isRecoveryRead ? BookieProtocol.FLAG_HIGH_PRIORITY : BookieProtocol.FLAG_NONE;
```

Recovery reads set `FLAG_HIGH_PRIORITY` but not `FLAG_DO_FENCING`. This means a bookie that receives a recovery read is NOT fenced by it. The BookKeeper fencing protocol assumes that once a quorum of bookies has been contacted in the fencing phase (Phase 1 LAC reads), all relevant bookies are fenced. But if a fencing LAC request is lost or delayed to one bookie (b3), that bookie enters Phase 2 without being fenced.

When Phase 2 recovery reads reach b3 (without the fencing flag), b3 serves the read but remains unfenced. If the original writer (w1) subsequently sends a write to b3 and one other bookie, it can reach ack quorum after the recovering writer has already seen empty state. The recovering writer closes the ledger as empty, truncating the committed entry.

The TLA+ specification found this flaw: the invariant "no committed entry is lost after recovery" is violated when recovery reads don't fence the bookies they read from.

## Diagnosis chain

1. **TLA+ violation**: The model checker found a trace where `w1` gets `ack quorum` after `w2` closes the ledger as empty. The trace shows `w2` performs recovery reads but `b3` is never fenced.
2. **Code path**: `LedgerHandle.recover()` → `ReadLastConfirmedOp` (Phase 1) → `PendingReadOp` (Phase 2 recovery reads). Phase 2 uses `PendingReadOp` with `isRecoveryRead=true`.
3. **Flag inspection**: `PendingReadOp.sendReadTo()` only sets `FLAG_HIGH_PRIORITY` for recovery reads — `FLAG_DO_FENCING` is absent.
4. **Root cause confirmed**: Without `FLAG_DO_FENCING`, the bookie's `readEntry()` handler does not call `fence()` on the ledger. The bookie remains writable for the original writer.
5. **Fix**: Add `FLAG_DO_FENCING` to recovery read flags. Bookie's `readEntry()` with this flag calls `fence()` before serving the read, closing the window.

## Fix description

The fix changes `PendingReadOp.sendReadTo()` to set `FLAG_HIGH_PRIORITY | FLAG_DO_FENCING` for all recovery reads. The bookie protocol handler treats a read with `FLAG_DO_FENCING` as an implicit fence operation: it fences the ledger before returning the entry. This ensures that any bookie that participates in Phase 2 recovery reads is fenced, regardless of whether the Phase 1 LAC fencing request was delivered to that bookie.

## How to apply

```bash
git checkout 017307bc67431a7616861ad09927c4e3327633d1
```

## How to verify

Run `reproduce.sh` — should print `PASS: Bug is fixed`.
