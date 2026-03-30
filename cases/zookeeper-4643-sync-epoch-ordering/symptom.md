# Symptom

A follower that crashes during the ZAB synchronization phase can later be elected leader with incomplete transaction history despite having a higher epoch, causing committed transactions to be silently truncated when it issues TRUNC commands to other followers.

## Observable behavior

- After a follower receives a DIFF sync and processes NEWLEADER, it updates its `currentEpoch` on disk *before* persisting the synced transactions to the transaction log
- If the follower crashes between updating the epoch and persisting transactions, upon restart it has a higher epoch but missing transactions
- When this follower is later elected leader (justified by its higher epoch), it sends TRUNC commands to followers that actually have the full transaction history, causing data loss
- The bug manifests as missing znodes or data that was committed by the previous leader
- The issue is most easily triggered during a sequence of leader elections and follower restarts
- JIRA reports describe a scenario with 3 rounds of crash/restart where the data loss becomes apparent
