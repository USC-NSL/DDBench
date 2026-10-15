# Code Investigation

## What was searched
The symptom describes messages that reached a consumer's max-deliver limit without being acknowledged disappearing from an R3 WorkQueue stream. Searched for the places where the server acks (and for WorkQueue streams, removes) stream messages on behalf of a consumer, and read the periodic consumer-state check that is one of those callers.

## What was found
```
$ grep -n "\.ackMsg(" server/*.go | grep -v _test.go
server/consumer.go:3417:				mset.ackMsg(o, seq)
server/consumer.go:3420:			mset.ackMsg(o, sseq)
server/consumer.go:6499:				didRemove := mset.ackMsg(o, seq)
server/consumer.go:6509:					mset.ackMsg(o, seq)
server/jetstream_cluster.go:5986:			mset.ackMsg(o, seq)
server/jetstream_cluster.go:5989:		mset.ackMsg(o, sseq)
server/stream.go:7002:				mset.ackMsg(nil, seq)
```

```
$ cat -n server/consumer.go | sed -n '6434,6529p'
  6434	// If we are a consumer of an interest or workqueue policy stream, process that state and make sure consistent.
  6435	func (o *consumer) checkStateForInterestStream(ss *StreamState) error {
  6436		o.mu.RLock()
  6437		// See if we need to process this update if our parent stream is not a limits policy stream.
  6438		mset := o.mset
  6439		shouldProcessState := mset != nil && o.retention != LimitsPolicy
  6440		if o.closed || !shouldProcessState || o.store == nil || ss == nil {
  6441			o.mu.RUnlock()
  6442			return nil
  6443		}
  6444		store := mset.store
  6445		state, err := o.store.State()
  6446	
  6447		filters, subjf, filter := o.filters, o.subjf, _EMPTY_
  6448		var wc bool
  6449		if filters == nil && subjf != nil {
  6450			filter, wc = subjf[0].subject, subjf[0].hasWildcard
  6451		}
  6452		chkfloor := o.chkflr
  6453		o.mu.RUnlock()
  6454	
  6455		if err != nil {
  6456			return err
  6457		}
  6458	
  6459		asflr := state.AckFloor.Stream
  6460		// Protect ourselves against rolling backwards.
  6461		if asflr&(1<<63) != 0 {
  6462			return errAckFloorInvalid
  6463		}
  6464		dflr := asflr
  6465		if len(state.Pending) > 0 && state.Delivered.Stream > dflr {
  6466			dflr = state.Delivered.Stream
  6467		}
  6468	
  6469		// Check if the underlying stream's last sequence is less than our floor.
  6470		// This can happen if the stream has been reset and has not caught up yet.
  6471		if asflr > ss.LastSeq {
  6472			return errAckFloorHigherThanLastSeq
  6473		}
  6474	
  6475		var smv StoreMsg
  6476		var seq, nseq uint64
  6477		// Start at first stream seq or a previous check floor, whichever is higher.
  6478		// Note this will really help for interest retention, with WQ the loadNextMsg
  6479		// gets us a long way already since it will skip deleted msgs not for our filter.
  6480		fseq := ss.FirstSeq
  6481		if chkfloor > fseq {
  6482			fseq = chkfloor
  6483		}
  6484	
  6485		var retryAsflr uint64
  6486		for seq = fseq; dflr > 0 && seq <= dflr; seq++ {
  6487			if filters != nil {
  6488				_, nseq, err = store.LoadNextMsgMulti(filters, seq, &smv)
  6489			} else {
  6490				_, nseq, err = store.LoadNextMsg(filter, wc, seq, &smv)
  6491			}
  6492			// if we advanced sequence update our seq. This can be on no error and EOF.
  6493			if nseq > seq {
  6494				seq = nseq
  6495			}
  6496			if err == nil {
  6497				// Only ack though if no error and seq <= ack floor.
  6498				if seq <= asflr {
  6499					didRemove := mset.ackMsg(o, seq)
  6500					// Removing the message could fail. For example if clustered since we need to propose it.
  6501					// Overwrite retry floor (only the first time) to allow us to check next time if the removal was successful.
  6502					if didRemove && retryAsflr == 0 {
  6503						retryAsflr = seq
  6504					}
  6505				} else if seq <= dflr {
  6506					// If we have pending, we will need to walk through to delivered in case we missed any of those acks as well.
  6507					if _, ok := state.Pending[seq]; !ok {
  6508						// The filters are already taken into account,
  6509						mset.ackMsg(o, seq)
  6510					}
  6511				}
  6512			} else if err == ErrStoreEOF {
  6513				break
  6514			}
  6515		}
  6516		// If retry floor was not overwritten, set to ack floor+1, we don't need to account for any retries below it.
  6517		if retryAsflr == 0 {
  6518			retryAsflr = asflr + 1
  6519		}
  6520	
  6521		o.mu.Lock()
  6522		// Update our check floor.
  6523		// Check floor must never be greater than ack floor+1, otherwise subsequent calls to this function would skip work.
  6524		if retryAsflr > o.chkflr {
  6525			o.chkflr = retryAsflr
  6526		}
  6527		o.mu.Unlock()
  6528		return nil
  6529	}
```

## Developer hypothesis
Several paths can ack a message on behalf of a consumer, which for WorkQueue retention removes it from the stream. Worth checking how each of these paths treats messages that hit the consumer's max-deliver limit without ever being acknowledged.
