# Code Investigation

## What was searched
The symptom describes messages being silently lost in a WorkQueue R3 stream when consumers reach their max-deliver limit. Investigated how `ackMsg` handles WorkQueue retention and how `checkStateForInterestStream` interacts with messages that exceeded max delivery.

## What was found
```
$ sed -n "7676,7685p" server/stream.go   # ackMsg WorkQueue case
	var shouldRemove bool
	switch mset.cfg.Retention {
	case WorkQueuePolicy:
		// Normally we just remove a message when its ack'd here but if we have direct consumers
		// from sources and/or mirrors we need to make sure they have delivered the msg.
		shouldRemove = mset.directs <= 0 || mset.noInterest(seq, o)
	case InterestPolicy:
		shouldRemove = mset.noInterest(seq, o)
	}

$ sed -n "6488,6510p" server/consumer.go   # checkStateForInterestStream loop
	for seq = fseq; dflr > 0 && seq <= dflr; seq++ {
		...
		if err == nil {
			if seq <= asflr {
				didRemove := mset.ackMsg(o, seq)
				...
			} else if seq <= dflr {
				// If we have pending, we will need to walk through to delivered
				// in case we missed any of those acks as well.
				if _, ok := state.Pending[seq]; !ok {
					mset.ackMsg(o, seq)       // <--- called for any delivered, non-pending seq
				}
			}
		}
	}

$ sed -n "2153,2175p" server/consumer.go   # hasMaxDeliveries
func (o *consumer) hasMaxDeliveries(seq uint64) bool {
	...
	if dc := o.deliveryCount(seq); dc >= o.maxdc {
		...
		if p, ok := o.pending[seq]; ok && p != nil {
			delete(o.pending, seq)         // <--- removes from pending
			o.updateDelivered(p.Sequence, seq, dc, p.Timestamp)
		}
		if o.rdc == nil {
			o.rdc = make(map[uint64]uint64)
		}
```
