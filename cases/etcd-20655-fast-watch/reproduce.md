# Reproduce: etcd #20655

## Step 1: Check out the reproduction test

The reproduction test is in PR #20654:
```bash
cd etcd

# Cherry-pick or apply the test from PR #20654
# The test rapidly creates watches and checks for dropped events
```

## Step 2: Run the reproduction test

```bash
# Run against the release-3.5 branch
go test -v -run TestWatchReliabilityHighFrequency ./tests/integration/ -count=1 -timeout 300s
```

Alternatively, write a manual repro:

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

## Step 3: Start etcd and run the test

```bash
# Start a single-node etcd
bin/etcd --data-dir /tmp/etcd-watch-test &
sleep 2

# Run the repro
cd /tmp && go run watch_race_test.go
```

## Expected result (bug present)
Some watch events are dropped (non-zero dropped count). The test reports missed events.
