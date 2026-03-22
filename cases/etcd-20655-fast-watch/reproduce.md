# Reproduce: etcd #20655

## Step 1: Run the manual reproduction test

**Note:** The test `TestWatchReliabilityHighFrequency` referenced in PR #20654 is not checked into the etcd repository. Use the manual reproduction below instead.

First, start a single-node etcd server (see setup.md), then run the following Go program:

```bash
cat > /tmp/watch_race_test.go << 'GOEOF'
package main

import (
    "context"
    "fmt"
    "sync"
    "time"

    clientv3 "go.etcd.io/etcd/client/v3"
)

func main() {
    cli, err := clientv3.New(clientv3.Config{
        Endpoints:   []string{"http://127.0.0.1:2379"},
        DialTimeout: 5 * time.Second,
    })
    if err != nil {
        panic(err)
    }
    defer cli.Close()

    ctx := context.Background()
    dropped := 0
    total := 100
    var mu sync.Mutex
    var wg sync.WaitGroup

    for i := 0; i < total; i++ {
        wg.Add(1)
        go func(idx int) {
            defer wg.Done()
            key := fmt.Sprintf("/test/key-%d", idx)

            // Create watch
            wch := cli.Watch(ctx, key, clientv3.WithCreatedNotify())
            <-wch // wait for created

            // Put a value
            cli.Put(ctx, key, fmt.Sprintf("value-%d", idx))

            // Check if we get the event
            select {
            case resp := <-wch:
                if len(resp.Events) == 0 {
                    mu.Lock()
                    dropped++
                    mu.Unlock()
                }
            case <-time.After(5 * time.Second):
                mu.Lock()
                dropped++
                mu.Unlock()
            }
        }(i)
    }
    wg.Wait()
    fmt.Printf("Dropped events: %d/%d\n", dropped, total)
    if dropped > 0 {
        fmt.Println("BUG: Watch events were dropped!")
    }
}
GOEOF
```

## Step 2: Start etcd and run the test

```bash
# Start a single-node etcd
bin/etcd --data-dir /tmp/etcd-watch-test &
sleep 2

# Run the repro (increase total for more likelihood of triggering)
cd /tmp && go run watch_race_test.go
```

**Note:** This race condition is internal to the watch subsystem and may require hundreds or thousands of rapid watch creations to trigger. Increase the `total` variable (e.g., to 500 or 1000) and run multiple times. The bug is non-deterministic.

## Expected result (bug present)
Some watch events are dropped (non-zero dropped count). The test reports missed events.
