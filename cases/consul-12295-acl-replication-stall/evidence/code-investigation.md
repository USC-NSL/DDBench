# Code Investigation

## What was searched
The symptom describes ACL replication routines not restarting when the same server loses and regains leadership in quick succession. A developer would investigate the routine manager's `Start` method to see how it handles re-starting a routine that is in the process of shutting down.

## What was found

The `running()` method in `lib/routine/routine.go` only checks the `stoppedCh` channel:

```go
// lib/routine/routine.go:21-27
func (r *routineTracker) running() bool {
    select {
    case <-r.stoppedCh:
        return false
    default:
        return true
    }
}
```

The `Start` method uses `running()` as a guard to skip re-starting:

```go
// lib/routine/routine.go:67-87
func (m *Manager) Start(ctx context.Context, name string, routine Routine) error {
    m.lock.Lock()
    defer m.lock.Unlock()

    if instance, ok := m.routines[name]; ok && instance.running() {
        return nil    // <-- returns early if "running"
    }

    if ctx == nil {
        ctx = context.Background()
    }

    rtCtx, cancel := context.WithCancel(ctx)
    instance := &routineTracker{
        cancel:    cancel,
        stoppedCh: make(chan struct{}),
    }

    go m.execute(rtCtx, name, routine, instance.stoppedCh)
    m.routines[name] = instance
    m.logger.Info("started routine", "routine", name)
    return nil
}
```

The `execute` method closes `stoppedCh` only after the routine function returns:

```go
// lib/routine/routine.go:90-101
func (m *Manager) execute(ctx context.Context, name string, routine Routine, done chan struct{}) {
    defer func() {
        close(done)    // <-- stoppedCh closed AFTER routine returns
    }()

    err := routine(ctx)
    ...
}
```

Note that `running()` does not check `rtCtx` cancellation — it only checks whether `stoppedCh` is closed, which happens after the goroutine fully exits. A routine whose context is already cancelled would still appear as "running" until `close(done)` executes.

## Developer hypothesis
The `running()` check in the routine manager's `Start` method and the signals it considers when determining whether a routine is still active.
