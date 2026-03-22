# Reproduce: NATS #7718

## Prerequisites
A 3-node NATS cluster with JetStream and overlapping stream imports (see setup.md).

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
