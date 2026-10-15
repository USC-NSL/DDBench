# Test Output

Obtained by running a 5-node NATS cluster, creating an interest-based R5 stream, adding a consumer with `--filter="events.a"`, editing the filter to `--filter="events.b"`, stepping down the stream leader, then publishing to `events.b` and attempting to consume.

## Output

```
$ nats stream add TEST --subjects="events.>" --retention=interest --replicas=5 --storage=file --defaults
Stream TEST was created

$ nats consumer add TEST myconsumer --filter="events.a" --ack=explicit --deliver=all --replay=instant --pull

$ nats consumer edit TEST myconsumer --filter="events.b"

$ nats stream cluster step-down TEST

Cluster Information:

                  Name: test-cluster
                Leader: n4
               Replica: n1, current, seen 486ms ago
               Replica: n2, current, seen 486ms ago
               Replica: n3, current, seen 486ms ago
               Replica: n5, current, seen 486ms ago

$ nats pub events.b "test-message"

$ nats consumer next TEST myconsumer --timeout=5s
nats: error: could not load consumer "myconsumer": consumer not found (10014)
```
