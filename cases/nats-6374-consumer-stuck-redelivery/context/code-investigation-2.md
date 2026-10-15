# Code Investigation

## What was searched
The symptom's second scenario is a consumer that becomes very slow or appears stuck when a message scheduled for redelivery has been deleted from the stream. Looked at how the delivery loop picks the next message, starting with the redelivery branch of `getNextMsg()` and how `loopAndGatherMsgs()` handles its errors.

## What was found
```
$ cat -n server/consumer.go | sed -n '4001,4040p'
  4001	func (o *consumer) getNextMsg() (*jsPubMsg, uint64, error) {
  4002		if o.mset == nil || o.mset.store == nil {
  4003			return nil, 0, errBadConsumer
  4004		}
  4005		// Process redelivered messages before looking at possibly "skip list" (deliver last per subject)
  4006		if o.hasRedeliveries() {
  4007			var seq, dc uint64
  4008			for seq = o.getNextToRedeliver(); seq > 0; seq = o.getNextToRedeliver() {
  4009				dc = o.incDeliveryCount(seq)
  4010				if o.maxdc > 0 && dc > o.maxdc {
  4011					// Only send once
  4012					if dc == o.maxdc+1 {
  4013						o.notifyDeliveryExceeded(seq, dc-1)
  4014					}
  4015					// Make sure to remove from pending.
  4016					if p, ok := o.pending[seq]; ok && p != nil {
  4017						delete(o.pending, seq)
  4018						o.updateDelivered(p.Sequence, seq, dc, p.Timestamp)
  4019					}
  4020					continue
  4021				}
  4022				if seq > 0 {
  4023					pmsg := getJSPubMsgFromPool()
  4024					sm, err := o.mset.store.LoadMsg(seq, &pmsg.StoreMsg)
  4025					if sm == nil || err != nil {
  4026						pmsg.returnToPool()
  4027						pmsg, dc = nil, 0
  4028						// Adjust back deliver count.
  4029						o.decDeliveryCount(seq)
  4030					}
  4031					return pmsg, dc, err
  4032				}
  4033			}
  4034		}
  4035	
  4036		// Check if we have max pending.
  4037		if o.maxp > 0 && len(o.pending) >= o.maxp {
  4038			// maxp only set when ack policy != AckNone and user set MaxAckPending
  4039			// Stall if we have hit max pending.
  4040			return nil, 0, errMaxAckPending
```

```
$ cat -n server/consumer.go | sed -n '4460,4487p'
  4460			// Grab our next msg.
  4461			pmsg, dc, err = o.getNextMsg()
  4462	
  4463			// We can release the lock now under getNextMsg so need to check this condition again here.
  4464			if o.closed || o.mset == nil {
  4465				o.mu.Unlock()
  4466				return
  4467			}
  4468	
  4469			// On error either wait or return.
  4470			if err != nil || pmsg == nil {
  4471				// On EOF we can optionally fast sync num pending state.
  4472				if err == ErrStoreEOF {
  4473					o.checkNumPendingOnEOF()
  4474				}
  4475				if err == ErrStoreMsgNotFound || err == errDeletedMsg || err == ErrStoreEOF || err == errMaxAckPending {
  4476					goto waitForMsgs
  4477				} else if err == errPartialCache {
  4478					s.Warnf("Unexpected partial cache error looking up message for consumer '%s > %s > %s'",
  4479						o.mset.acc, stream, o.cfg.Name)
  4480					goto waitForMsgs
  4481	
  4482				} else {
  4483					s.Errorf("Received an error looking up message for consumer '%s > %s > %s': %v",
  4484						o.mset.acc, stream, o.cfg.Name, err)
  4485					goto waitForMsgs
  4486				}
  4487			}
```

## Developer hypothesis
Redelivered sequences are taken from the redelivery queue and loaded from the store before being sent. Worth checking how this path behaves for sequences that are no longer present in the stream.
