# Symptom

A quorum queue member crashes after installing a Raft snapshot. The crash occurs in `rabbit_fifo:delivery_effect/3` when a slow or previously stopped follower restarts, installs a snapshot from the leader, and then tries to deliver messages to local consumers that no longer exist in the log.

## Error signature

The crash manifests as a `lists:zipwith` failure because the log returns fewer entries than the delivery effect requests:

```
** Stacktrace =
**  [{lists,zipwith,
            [#Fun<rabbit_fifo.60.126061837>,[],
             [{1,[7352901|4]},{2,[7352904|4]}],
             fail],
            [{file,"lists.erl"},{line,844}]},
     {lists,zipwith,4,[{file,"lists.erl"},{line,845}]},
     {rabbit_fifo,'-delivery_effect/3-anonymous-5-',4,
                  [{file,"rabbit_fifo.erl"},{line,2062}]},
     {ra_server_proc,handle_effect,5,
                     [{file,"src/ra_server_proc.erl"},{line,1385}]},
     {lists,foldl,3,[{file,"lists.erl"},{line,2146}]},
     {ra_server_proc,handle_effects,5,
                     [{file,"src/ra_server_proc.erl"},{line,1301}]}]
```

## Observable behavior

1. A follower that was stopped or running slowly restarts and installs a Raft snapshot from the leader.
2. The snapshot contains references to consumers on the follower's node that subscribed while it was down.
3. After applying the snapshot, the follower tries to read log entries for messages that were already consumed and checkpointed on the leader.
4. The `delivery_effect/3` function calls `lists:zipwith` with the log results and the requested message list. Because the log entries were already truncated by the checkpoint, the log returns an empty list or fewer entries than requested.
5. `lists:zipwith` crashes because the two lists have different lengths.
6. The quorum queue member process crashes. It may recover by restarting, but this is also considered a bug since the stale read should be handled gracefully.

## Trigger conditions

- A 3-node quorum queue cluster
- A follower that is stopped or slow
- Messages are published and consumed while the follower is down
- A checkpoint is forced on the leader (truncating log entries)
- A consumer is attached to the follower's node while the follower is stopped
- The follower restarts and installs the snapshot
