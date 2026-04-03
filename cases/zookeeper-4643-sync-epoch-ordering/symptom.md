# Symptom

A follower that crashes during leader-follower synchronization can later be elected leader with incomplete transaction history, causing committed transactions to be silently lost when it forces other followers to truncate their logs to match.

## Observable behavior

- A follower joins the cluster and begins synchronizing with the leader.
- If the follower crashes partway through synchronization and then restarts, it may appear to have a more recent epoch than other nodes despite missing committed transactions.
- When this follower is later elected leader (justified by its apparently higher epoch), it instructs other followers to discard transactions that it does not have, causing data loss.
- The bug manifests as missing znodes or data that was committed by the previous leader.
- The issue is most easily triggered during a sequence of leader elections and follower restarts.
- Reproduction scenarios involve 3 rounds of crash/restart where the data loss becomes apparent.
