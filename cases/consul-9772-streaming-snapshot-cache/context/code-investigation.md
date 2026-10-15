# Code Investigation

## What was searched
The symptom describes fresh subscribers (`Index=0`) intermittently receiving the reset framing event that is meant only for subscribers reconnecting with a stale index, and only when the two kinds of subscription arrive close together. Read how `EventPublisher.Subscribe` builds and serves the initial snapshot for each kind of subscriber.

## What was found
```
$ cat -n agent/consul/stream/event_publisher.go | sed -n '144,201p'
   144			e.topicBuffers[topic] = buf
   145		}
   146		return buf
   147	}
   148	
   149	// Subscribe returns a new Subscription for the given request. A subscription
   150	// will receive an initial snapshot of events matching the request if req.Index > 0.
   151	// After the snapshot, events will be streamed as they are created.
   152	// Subscriptions may be closed, forcing the client to resubscribe (for example if
   153	// ACL policies changed or the state store is abandoned).
   154	//
   155	// When the caller is finished with the subscription for any reason, it must
   156	// call Subscription.Unsubscribe to free ACL tracking resources.
   157	func (e *EventPublisher) Subscribe(req *SubscribeRequest) (*Subscription, error) {
   158		handler, ok := e.snapshotHandlers[req.Topic]
   159		if !ok || req.Topic == nil {
   160			return nil, fmt.Errorf("unknown topic %v", req.Topic)
   161		}
   162	
   163		e.lock.Lock()
   164		defer e.lock.Unlock()
   165	
   166		topicHead := e.getTopicBuffer(req.Topic).Head()
   167	
   168		// If the client view is fresh, resume the stream.
   169		if req.Index > 0 && topicHead.HasEventIndex(req.Index) {
   170			buf := newEventBuffer()
   171			subscriptionHead := buf.Head()
   172			// splice the rest of the topic buffer onto the subscription buffer so
   173			// the subscription will receive new events.
   174			buf.AppendItem(topicHead.NextLink())
   175			return e.subscriptions.add(req, subscriptionHead), nil
   176		}
   177	
   178		snapFromCache := e.getCachedSnapshotLocked(req)
   179		if req.Index == 0 && snapFromCache != nil {
   180			return e.subscriptions.add(req, snapFromCache.First), nil
   181		}
   182		snap := newEventSnapshot()
   183	
   184		// if the request has an Index the client view is stale and must be reset
   185		// with a NewSnapshotToFollow event.
   186		if req.Index > 0 {
   187			snap.buffer.Append([]Event{{
   188				Topic:   req.Topic,
   189				Payload: newSnapshotToFollow{},
   190			}})
   191	
   192			if snapFromCache != nil {
   193				snap.buffer.AppendItem(snapFromCache.First)
   194				return e.subscriptions.add(req, snap.First), nil
   195			}
   196		}
   197	
   198		snap.appendAndSplice(*req, handler, topicHead)
   199		e.setCachedSnapshotLocked(req, snap)
   200		return e.subscriptions.add(req, snap.First), nil
   201	}
```

## Developer hypothesis
`Subscribe()` handles both `Index=0` and `Index>0` requests and shares recently built snapshots between subscribers through a per-request snapshot cache. The time-dependence in the symptom suggests looking at how that cache interacts with the two subscription modes.
