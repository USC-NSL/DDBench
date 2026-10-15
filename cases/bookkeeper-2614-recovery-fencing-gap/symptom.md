# Symptom

In an Apache BookKeeper cluster with write quorum (Qw) of 3 and ack quorum (Qa) of 2, a committed entry can be silently truncated during ledger recovery, resulting in data loss that is invisible to the original writer.

## Observable behavior

- An entry acknowledged as successfully written by the original writer (w1) disappears after a second writer (w2) completes ledger recovery and closes the ledger.
- From the client side: w1 receives a successful write acknowledgment, meaning the entry reached write quorum. However, after w2 closes the recovered ledger, reads of that entry return an empty ledger or a ledger that ends before the acknowledged entry.
- The data loss only occurs under a specific interleaving: ledger recovery begins (w2 fences a write quorum of bookies and performs recovery reads), but one bookie is not yet fenced when w1 sends its final write to reach ack quorum. That one bookie accepts w1's write after the recovery reads have already seen empty state.
- The condition requires at least one bookie in every ack quorum to have missed a fencing request — which can happen if a fence network message is delayed or lost.
- The original writer does not observe any error. Its write succeeds normally and it reports the entry as committed to its caller.
- The recovered ledger contains fewer entries than were committed, with no error or corruption marker. Downstream readers see a shorter ledger than expected, leading to incorrect application state.
- Discovered through TLA+ formal model checking of the BookKeeper replication protocol; reproducible with a controlled two-writer scenario using mock bookies.
