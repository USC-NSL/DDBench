# Symptom: NATS #6888

After ungraceful termination (`kill -9`) and restart of NATS server nodes in a JetStream cluster, streams can be completely lost (forgotten by the cluster). The streams:

1. No longer appear in `nats stream ls` output.
2. Return empty results from the JetStream API's `getStreamNames()`.
3. The stream data files may still exist on disk, but the Raft meta-stream has lost track of them.
4. The streams cannot be accessed, consumed from, or managed.

This is a data loss scenario: the streams and all their messages become inaccessible after a `kill -9` + restart cycle, even though the data may still be on disk. The issue is in the Raft meta-stream consistency, not in the actual stream data.
