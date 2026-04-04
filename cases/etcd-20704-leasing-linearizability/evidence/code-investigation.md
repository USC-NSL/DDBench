# Code Investigation

## What was searched
The symptom describes linearizability violations in the leasing cache under concurrent modifications. A developer would investigate the synchronization between cache reads (`Get`) and cache mutations (`Update`/`Delete`) via the `waitc` channel mechanism.

## What was found

The `Get` path in `client/v3/leasing/cache.go` reads cached data after waiting on the `waitc` channel:

```go
// client/v3/leasing/cache.go:198-216
func (lc *leaseCache) Get(ctx context.Context, op v3.Op) (*v3.GetResponse, bool) {
    if isBadOp(op) {
        return nil, false
    }
    key := string(op.KeyBytes())
    li, wc := lc.notify(key)       // (1) grabs li pointer + waitc under RLock
    if li == nil {
        return nil, true
    }
    select {
    case <-wc:                      // (2) waits for in-progress mutation — NO lock held
    case <-ctx.Done():
        return nil, true
    }
    lc.mu.RLock()
    lk := *li                       // (3) reads li's data under RLock
    ret := lk.get(op)
    lc.mu.RUnlock()
    return ret, true
}
```

The `notify` function captures the `li` pointer and `waitc` under `RLock`:

```go
// client/v3/leasing/cache.go:242-249
func (lc *leaseCache) notify(key string) (*leaseKey, <-chan struct{}) {
    lc.mu.RLock()
    defer lc.mu.RUnlock()
    if li := lc.entries[key]; li != nil {
        return li, li.waitc
    }
    return nil, nil
}
```

The `put` path in `client/v3/leasing/kv.go` updates the cache and then signals waiters:

```go
// client/v3/leasing/kv.go:232-257
func (lkv *leasingKV) put(ctx context.Context, op v3.Op) (pr *v3.PutResponse, err error) {
    ...
    for ctx.Err() == nil {
        resp, wc, err := lkv.tryModifyOp(ctx, op)
        ...
        if resp.Succeeded {
            lkv.leases.mu.Lock()
            lkv.leases.Update(op.KeyBytes(), op.ValueBytes(), resp.Header)
            lkv.leases.mu.Unlock()       // (A) cache updated, lock released
            ...
        }
        if wc != nil {
            close(wc)                      // (B) signals waiters AFTER releasing lock
        }
        ...
    }
}
```

The `Update` function modifies the cached response in-place:

```go
// client/v3/leasing/cache.go:139-157
func (lc *leaseCache) Update(key, val []byte, respHeader *v3pb.ResponseHeader) {
    li := lc.entries[string(key)]
    ...
    cacheResp.Kvs[0].Version++
    if cacheResp.Kvs[0].ModRevision < respHeader.Revision {
        cacheResp.Header = respHeader
        cacheResp.Kvs[0].ModRevision = respHeader.Revision
        cacheResp.Kvs[0].Value = val
    }
}
```

Note that between step (B) (`close(wc)`) and step (3) (when `Get` re-acquires `RLock`), no lock is held — the notification and the subsequent read happen in separate critical sections.

## Developer hypothesis
The lock acquire/release pattern around the `waitc` notification and subsequent cache read in `Get`.
