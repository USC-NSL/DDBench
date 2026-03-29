# Reproduce: RabbitMQ #12635

The bug is reproduced via Common Test injection. The `gh_12635` test case from the fix PR is injected into `deps/rabbit/test/quorum_queue_SUITE.erl` and runs within the `cluster_size_3` test group, which starts a real 3-node RabbitMQ cluster.

## Bug: Quorum queue crash after Raft snapshot installation

### Setup

The test starts a 3-node RabbitMQ cluster with `quorum_min_checkpoint_interval` set to 1 (enabling immediate checkpoints). It creates a quorum queue on the cluster.

### Trigger

The following sequence reproduces the crash:

1. **Stop follower:** Stop the Ra server (Raft member) on the third node to simulate a slow/down follower.
2. **Publish messages:** Publish 2 messages to the quorum queue on the leader.
3. **Force checkpoint:** Trigger a checkpoint on the leader, which truncates log entries for the consumed messages.
4. **Publish one more message.**
5. **Attach/detach consumer on stopped node:** Open a channel on the stopped node, subscribe to the queue, then close the channel. This assigns messages to the consumer in the queue's state, but since the member is down, no messages are actually delivered. The consumer references are part of the queue state that gets snapshotted.
6. **Purge the queue:** Remove all remaining messages on the leader.
7. **Restart follower:** Restart the Ra server on the third node. It installs the snapshot from the leader, which includes consumer references to messages whose log entries have already been truncated.

### Expected result (bug present)

The follower member crashes with a `lists:zipwith` error in `delivery_effect/3`. The log returns fewer entries than the delivery effect requests because the referenced log entries were truncated by the checkpoint. The test detects this as a `DOWN` monitor message from the Ra server process.

### Test command

```bash
cd /path/to/rabbitmq-server
# After injecting the test (done automatically by reproduce.sh)
# erlang.mk uses t=group:case for filtering within groups
make -C deps/rabbit ct-quorum_queue t=cluster_size_3:gh_12635
```

## Manual reproduction (from issue #12635)

These are the original manual steps from the issue report, using Erlang shell commands:

1. Create a quorum queue `q1` in a 3-node cluster with `quorum_min_checkpoint_interval` set to 1
2. Stop the member on node 3: `ra:stop_server(quorum_queues, {'%2F_q1', node()}).`
3. Publish 2 messages
4. Force checkpoint: `ra:cast_aux_command({'%2F_q1', 'rabbit-1@HOST'}, force_checkpoint).`
5. Publish 1 more message
6. Attach then detach a consumer connected to node 3
7. Purge the queue
8. Restart the member: `ra:restart_server(quorum_queues, {'%2F_q1', node()}).`
9. Observe the member crash on node 3
