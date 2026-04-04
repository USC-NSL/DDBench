# Code Investigation

## What was searched
The symptom describes a consumer becoming stuck when redelivering deleted messages. Investigated what happens when `getNextMsg` tries to redeliver a message that has been deleted from the stream.

## What was found
```
$ sed -n "4001,4040p" server/consumer.go   # getNextMsg redelivery path
func (o *consumer) getNextMsg() (*jsPubMsg, uint64, error) {
	if o.mset == nil || o.mset.store == nil {
		return nil, 0, errBadConsumer
	}
	// Process redelivered messages before looking at possibly "skip list" (deliver last per subject)
	if o.hasRedeliveries() {
		var seq, dc uint64
		for seq = o.getNextToRedeliver(); seq > 0; seq = o.getNextToRedeliver() {
			dc = o.incDeliveryCount(seq)
			if o.maxdc > 0 && dc > o.maxdc {
				// Only send once
				if dc == o.maxdc+1 {
					o.notifyDeliveryExceeded(seq, dc-1)
				}
				// Make sure to remove from pending.
				if p, ok := o.pending[seq]; ok && p != nil {
					delete(o.pending, seq)
					o.updateDelivered(p.Sequence, seq, dc, p.Timestamp)
				}
				continue
			}
			if seq > 0 {
				pmsg := getJSPubMsgFromPool()
				sm, err := o.mset.store.LoadMsg(seq, &pmsg.StoreMsg)
				if sm == nil || err != nil {
					pmsg.returnToPool()
					pmsg, dc = nil, 0
					// Adjust back deliver count.
					o.decDeliveryCount(seq)
				}
				return pmsg, dc, err
			}
		}
	}

$ sed -n "4475,4480p" server/consumer.go   # caller error handling
			if err == ErrStoreMsgNotFound || err == errDeletedMsg || err == ErrStoreEOF || err == errMaxAckPending {
				goto waitForMsgs
```

When a deleted message is encountered during redelivery (LoadMsg returns error), `getNextMsg` returns `nil, 0, err`. Crucially, the sequence is NOT removed from `o.pending`, and the delivery count is decremented back. The caller sees `ErrStoreMsgNotFound` or `errDeletedMsg` and goes to `waitForMsgs`.

On the next delivery attempt, `getNextMsg` will again try to redeliver the same deleted sequence — it's still in the redelivery queue and still in pending.

## Developer hypothesis
The `getNextMsg` redelivery loop's error-handling path for deleted messages and its interaction with `o.pending` and the redelivery queue.
