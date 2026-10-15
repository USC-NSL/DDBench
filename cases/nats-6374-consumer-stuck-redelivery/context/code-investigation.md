# Code Investigation

## What was searched
The symptom's first scenario is a consumer that stops delivering after its leader steps down while acknowledgments are in flight and it later becomes leader again. Looked at how inbound acks are queued on the consumer and what the consumer tears down when it stops being leader (`setLeader(false)` in `server/consumer.go`).

## What was found
```
$ grep -n "ackMsgs" server/consumer.go
483:	ackMsgs *ipQueue[*jsAckMsg]
1052:	// Create ackMsgs queue now that we have a consumer name
1053:	o.ackMsgs = newIPQueue[*jsAckMsg](s, fmt.Sprintf("[ACC:%s] consumer '%s' on stream '%s' ackMsgs", accName, o.name, cfg.Name))
1550:			o.ackMsgs.drain()
2331:// Push the ack message to the consumer's ackMsgs queue
2334:	o.ackMsgs.push(newJSAckMsg(subject, reply, c.pa.hdr, copyBytes(rmsg)))
4312:		case <-o.ackMsgs.ch:
4313:			acks := o.ackMsgs.pop()
4318:			o.ackMsgs.recycle(&acks)
5653:	o.ackMsgs.unregister()
```

```
$ cat -n server/consumer.go | sed -n '1515,1556p'
  1515	
  1516		} else {
  1517			// Shutdown the go routines and the subscriptions.
  1518			o.mu.Lock()
  1519			if o.qch != nil {
  1520				close(o.qch)
  1521				o.qch = nil
  1522			}
  1523			// Stop any inactivity timers. Should only be running on leaders.
  1524			stopAndClearTimer(&o.dtmr)
  1525			// Stop any unpause timers. Should only be running on leaders.
  1526			stopAndClearTimer(&o.uptmr)
  1527			// Make sure to clear out any re-deliver queues
  1528			o.stopAndClearPtmr()
  1529			o.rdq = nil
  1530			o.rdqi.Empty()
  1531			o.pending = nil
  1532			// ok if they are nil, we protect inside unsubscribe()
  1533			o.unsubscribe(o.ackSub)
  1534			o.unsubscribe(o.reqSub)
  1535			o.unsubscribe(o.fcSub)
  1536			o.ackSub, o.reqSub, o.fcSub = nil, nil, nil
  1537			if o.infoSub != nil {
  1538				o.srv.sysUnsubscribe(o.infoSub)
  1539				o.infoSub = nil
  1540			}
  1541			// Reset waiting if we are in pull mode.
  1542			if o.isPullMode() {
  1543				o.waiting = newWaitQueue(o.cfg.MaxWaiting)
  1544				o.nextMsgReqs.drain()
  1545			} else if o.srv.gateway.enabled {
  1546				stopAndClearTimer(&o.gwdtmr)
  1547			}
  1548			// If we were the leader make sure to drain queued up acks.
  1549			if wasLeader {
  1550				o.ackMsgs.drain()
  1551				// Also remove any pending replies since we should not be the one to respond at this point.
  1552				o.replies = nil
  1553			}
  1554			o.mu.Unlock()
  1555		}
  1556	}
```

## Developer hypothesis
Inbound acks are queued and processed asynchronously, and step-down tears down a number of leader-only structures. Worth checking how in-flight ack handling and the state torn down here interact when the same consumer later becomes leader again.
