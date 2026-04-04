# Code Investigation

## What was searched
The symptom describes a consumer becoming stuck after leader step-down with inflight acks. Investigated whether the ack-wait-level counter (`o.awl`) is properly reset when leadership is relinquished.

## What was found
```
$ grep -n "o\.awl\|awl " server/consumer.go
394:	awl               int64
2333:	atomic.AddInt64(&o.awl, 1)
2339:	defer atomic.AddInt64(&o.awl, -1)
5081:	// We will now bail if we see an ack pending inbound to us via o.awl.
5085:		if check && atomic.LoadInt64(&o.awl) > 0 {

$ sed -n "1516,1545p" server/consumer.go   # setLeader(false) path
	} else {
		// Shutdown the go routines and the subscriptions.
		o.mu.Lock()
		if o.qch != nil {
			close(o.qch)
			o.qch = nil
		}
		// Stop any inactivity timers. Should only be running on leaders.
		stopAndClearTimer(&o.dtmr)
		// Stop any unpause timers. Should only be running on leaders.
		stopAndClearTimer(&o.uptmr)
		// Make sure to clear out any re-deliver queues
		o.stopAndClearPtmr()
		o.rdq = nil
		o.rdqi.Empty()
		o.pending = nil
		// ok if they are nil, we protect inside unsubscribe()
		o.unsubscribe(o.ackSub)
		o.unsubscribe(o.reqSub)
		o.unsubscribe(o.fcSub)
		o.ackSub, o.reqSub, o.fcSub = nil, nil, nil
```

In the `setLeader(false)` path, `o.pending` is set to nil and subscriptions are cleaned up, but `o.awl` is never reset to 0.

In the pending-check loop (`checkPending`, line 5085), when `len(o.pending) > 1024`, the loop checks `atomic.LoadInt64(&o.awl) > 0` and if true, resets the timer and returns early — effectively stalling all redelivery processing.

## Developer hypothesis
The `setLeader(false)` cleanup path and the per-leader state it resets, alongside the `o.awl` counter's role in `checkPending`.
