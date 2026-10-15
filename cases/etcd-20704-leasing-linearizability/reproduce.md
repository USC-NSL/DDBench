# Reproduce: etcd #20704

## Step 1: Start etcd

```bash
rm -rf /tmp/etcd-leasing-test
bin/etcd --data-dir /tmp/etcd-leasing-test &
sleep 2
```

## Step 2: Write a Go test for the Delete + Put race

```bash
cat > /tmp/leasing_bug_test.go << 'GOEOF'
package main

import (
    "context"
    "fmt"
    "sync"
    "time"

    clientv3 "go.etcd.io/etcd/client/v3"
    "go.etcd.io/etcd/client/v3/leasing"
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

    lkv, err := leasing.NewKV(cli, "leasing-test/")
    if err != nil {
        panic(err)
    }

    ctx := context.Background()
    key := "/test/leasing-key"
    bugFound := false

    for iter := 0; iter < 1000; iter++ {
        // Setup: put a value
        lkv.Put(ctx, key, "initial")

        var wg sync.WaitGroup
        wg.Add(2)

        // Goroutine 1: Delete the key
        go func() {
            defer wg.Done()
            lkv.Delete(ctx, key)
        }()

        // Goroutine 2: Put a new value
        go func() {
            defer wg.Done()
            lkv.Put(ctx, key, "new-value")
        }()

        wg.Wait()

        // Check: if the key was deleted last, Get should return empty
        // But the leasing cache may return stale data
        resp, _ := lkv.Get(ctx, key)

        // Also check directly against etcd
        directResp, _ := cli.Get(ctx, key)

        if len(resp.Kvs) != len(directResp.Kvs) {
            fmt.Printf("BUG at iteration %d: leasing cache says %d kvs, etcd says %d kvs\n",
                iter, len(resp.Kvs), len(directResp.Kvs))
            bugFound = true
            break
        }
    }

    if !bugFound {
        fmt.Println("No bug detected in 1000 iterations (may need more runs)")
    }
}
GOEOF
```

## Step 3: Run the test

```bash
cd /tmp && go run leasing_bug_test.go
```

## Expected result (bug present)
The test detects a mismatch between the leasing cache state and the actual etcd state, showing that `Get` returns incorrect data after concurrent `Delete` + `Put` operations.

## Oracle verdict

`./bench.sh reproduce etcd-20704-leasing-linearizability` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): in one of 1000 iterations of a concurrent `Delete` and `Put` on one key through a leasing KV against a single-node etcd, a following `Get` through the leasing KV returns a different number of keys than a direct `Get`; a leasing KV operation that returns an error, or a client program that hangs for 300 s or crashes, is also FAIL. A worktree that does not build, an etcd that does not start serving, or a client program that does not compile against the worktree's `client/v3/leasing` is also FAIL.
- **PASS** (exit 0): the leasing `Get` matches the direct `Get` in all 1000 iterations and the client program reports completion.
- **ERROR** (exit 2): the client program cannot connect to etcd or exits 0 without completing, Go module downloads fail, or the case is not set up (`REBUILD.sh` or the etcd binary is missing).
