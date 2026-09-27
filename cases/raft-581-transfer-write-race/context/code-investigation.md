# Code Investigation

## What was searched
The symptom describes the leader continuing to accept writes after initiating a leadership transfer. Investigated the interaction between the transfer mechanism, the Apply path, and the TimeoutNow flow.

## What was found

### Transfer initiation (raft.go:643-722)
```
$ sed -n "643,722p" raft.go

case future := <-r.leadershipTransferCh:
    ...
    r.setLeadershipTransferInProgress(true)
    go r.leadershipTransfer(*id, *address, state, stopCh, doneCh)
```

### Transfer goroutine cleanup (raft.go:678-700)
```go
go func() {
    defer r.setLeadershipTransferInProgress(false)
    select {
    case <-time.After(r.config().ElectionTimeout):
        close(stopCh)
        future.respond(err)
        <-doneCh
    case <-leftLeaderLoop:
        close(stopCh)
        future.respond(nil)
        <-doneCh
    case err := <-doneCh:
        future.respond(err)
    }
}()
```

### leadershipTransfer sends TimeoutNow (raft.go:928-967)
```go
func (r *Raft) leadershipTransfer(...) {
    // Wait for follower to catch up
    for atomic.LoadUint64(&repl.nextIndex) <= r.getLastIndex() {
        ...
    }
    // Send TimeoutNow message to target server
    err := r.trans.TimeoutNow(id, address, &TimeoutNowRequest{...}, &TimeoutNowResponse{})
    doneCh <- err
}
```

### Apply path checks transfer flag (raft.go:846-870)
```go
case newLog := <-r.applyCh:
    if r.getLeadershipTransferInProgress() {
        newLog.respond(ErrLeadershipTransferInProgress)
        continue
    }
    ...
    r.dispatchLogs(ready)
```

## Developer hypothesis
The timing of `setLeadershipTransferInProgress(false)` relative to the `TimeoutNow` RPC completion in the transfer cleanup goroutine.
