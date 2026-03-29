# Verification Criteria

## FAIL (bug present)

`reproduce.sh` exits with code 1 and prints:

```
FAIL: Bug is present — node campaigns despite pending conf change
```

The test `test_conf_change_check_before_campaign` fails: node 2 transitions to a non-Follower state after receiving `MsgTransferLeader` despite having an unapplied `RemoveNode` conf change in its log. The node campaigns with a stale voter set.

## PASS (bug fixed)

`reproduce.sh` exits with code 0 and prints:

```
PASS: Bug is fixed — pending conf change blocks campaign
```

The test passes: node 2 remains Follower while the conf change is pending, and only campaigns after the conf change has been applied.

## Verification invariant

The oracle verifies that the leader transfer protocol respects configuration change ordering:
1. A node must not campaign if there are pending unapplied configuration changes
2. Both election timeout (`MsgHup`) and leader transfer (`MsgTimeoutNow`) paths must enforce this check
3. After applying the configuration change, campaigning proceeds normally
