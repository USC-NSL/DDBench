# Reproduce: NATS #7718

## Prerequisites
Run inside `./bench.sh shell nats-7718-subscription-leak`, from `/workspace/src` (the `nats` CLI is preinstalled in the image). Start a 3-node NATS cluster with JetStream and overlapping stream imports.

`server1.conf`:
```
server_name: n1
listen: 0.0.0.0:4222
jetstream {
    store_dir: /tmp/nats-js-1
}
cluster {
    name: test-cluster
    listen: 0.0.0.0:6222
    routes: [
        nats://localhost:6222,
        nats://localhost:6223,
        nats://localhost:6224,
    ]
}
accounts {
    SYS { users: [{user: sys, password: sys}] }
    A {
        jetstream: enabled
        users: [{user: a, password: a}]
        exports: [
            {stream: "events.>"}
        ]
    }
    B {
        jetstream: enabled
        users: [{user: b, password: b}]
        imports: [
            {stream: {account: A, subject: "events.>"}}
            {stream: {account: A, subject: "events.critical.>"}}
        ]
    }
}
system_account: SYS
```

Create similar `server2.conf` and `server3.conf` with different ports (4223/6223, 4224/6224) and store dirs, then:

```bash
./nats-server -c server1.conf &
./nats-server -c server2.conf &
./nats-server -c server3.conf &
```

## Step 1: Create a stream in account A

```bash
nats -s nats://a:a@localhost:4222 stream add EVENTS \
  --subjects "events.>" \
  --storage file \
  --replicas 3 \
  --retention limits \
  --max-msgs -1 \
  --max-bytes -1 \
  --max-age 1h \
  --discard old
```

## Step 2: Publish some messages

```bash
for i in $(seq 1 100); do
    nats -s nats://a:a@localhost:4222 pub "events.critical.alert" "message $i"
done
```

## Step 3: Rapidly create and destroy OrderedConsumers in account B

```bash
# Record initial subscription count
INITIAL_SUBS=$(curl -s http://localhost:8222/varz | jq '.subscriptions')
echo "Initial subs: $INITIAL_SUBS"

# Rapidly create and destroy ordered consumers
for i in $(seq 1 200); do
    # Create an ordered consumer, read one message, then destroy it
    timeout 2 nats -s nats://b:b@localhost:4222 consumer sub EVENTS \
      --ordered --count 1 2>/dev/null &
    sleep 0.1
done
wait

sleep 5

# Check subscription count
FINAL_SUBS=$(curl -s http://localhost:8222/varz | jq '.subscriptions')
echo "Final subs: $FINAL_SUBS"
echo "Leaked: $((FINAL_SUBS - INITIAL_SUBS))"
```

## Step 4: Go client reproduction

```go
package main

import (
    "context"
    "fmt"
    "time"

    "github.com/nats-io/nats.go"
    "github.com/nats-io/nats.go/jetstream"
)

func main() {
    nc, _ := nats.Connect("nats://b:b@localhost:4222")
    js, _ := jetstream.New(nc)

    for i := 0; i < 500; i++ {
        ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
        cons, err := js.OrderedConsumer(ctx, "EVENTS", jetstream.OrderedConsumerConfig{})
        if err == nil {
            // Read one message
            cons.Next(jetstream.WithExpiry(500 * time.Millisecond))
            // Consumer goes out of scope (should be cleaned up)
        }
        cancel()
        time.Sleep(50 * time.Millisecond)
    }

    fmt.Println("Done creating/destroying consumers")
    nc.Close()
}
```

## Expected result (bug present)
The subscription count grows continuously. After 200+ consumer create/destroy cycles, the subscription count is significantly higher than the initial count (leaked by 100+ subscriptions).

## Oracle verdict

`./bench.sh reproduce nats-7718-subscription-leak` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): in a 3-node cluster where account `ACC` imports a stream on `>` from another account, 3 cycles of creating and deleting a stream and a consumer leave the servers' subscription counts changed (e.g. the count after deleting the stream grows from cycle to cycle), or the servers do not all report the expected count within 2 s. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): in all 3 cycles every server reports the same subscription count at each step, deleting the consumer restores the post-stream-create count, and each step's count is identical from cycle to cycle.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or the `nats-server` binary is missing), or Go module downloads fail so the oracle test cannot run.
