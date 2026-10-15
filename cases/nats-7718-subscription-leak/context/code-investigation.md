# Code Investigation

## What was searched
The symptom describes the server's subscription count growing without bound when OrderedConsumers are rapidly created and destroyed in an account with overlapping stream imports. Stream imports are implemented with "shadow" subscriptions in `server/client.go`, so searched for how shadow subscriptions are tracked and read the low-level `unsubscribe()` that tears them down.

## What was found
```
$ grep -n "shadow" server/client.go
637:	shadow  []*subscription // This is to track shadowed accounts.
3053:// subscription's subject, then add shadow subscriptions in the other accounts
3148:	var shadow []*subscription
3151:		shadow = make([]*subscription, 0, len(ims))
3157:		// We will create a shadow subscription.
3162:		shadow = append(shadow, nsub)
3165:	if shadow != nil {
3167:		sub.shadow = shadow
3174:// Add in the shadow subscription.
3206:		errs := fmt.Sprintf("Could not add shadow import subscription for account %q", im.acc.Name)
3333:	// Check to see if we have shadow subscriptions.
3336:	shadowSubs := sub.shadow
3337:	sub.shadow = nil
3338:	if len(shadowSubs) > 0 {
3345:	// Process shadow subs if we have them.
3346:	for _, nsub := range shadowSubs {
3348:			c.Debugf("Could not remove shadow import subscription for account %q", nsub.im.acc.Name)
3478:		// Remap subject if its a shadow subscription, treat like a normal client.
5031:		// Check for stream import mapped subs (shadow subs). These apply to local subs only.
5801:		oldShadows := sub.shadow
5802:		sub.shadow = nil
5908:					// Call unsubscribe here to cleanup shadow subscriptions and such.
```

```
$ cat -n server/client.go | sed -n '3307,3362p'
  3307	// Low level unsubscribe for a given client.
  3308	func (c *client) unsubscribe(acc *Account, sub *subscription, force, remove bool) {
  3309		if s := c.srv; s != nil && s.isShuttingDown() {
  3310			return
  3311		}
  3312	
  3313		c.mu.Lock()
  3314		if !force && sub.max > 0 && sub.nm < sub.max {
  3315			c.Debugf("Deferring actual UNSUB(%s): %d max, %d received", sub.subject, sub.max, sub.nm)
  3316			c.mu.Unlock()
  3317			return
  3318		}
  3319	
  3320		if c.trace {
  3321			c.traceOp("<-> %s", "DELSUB", sub.sid)
  3322		}
  3323	
  3324		// Remove accounting if requested. This will be false when we close a connection
  3325		// with open subscriptions.
  3326		if remove {
  3327			delete(c.subs, bytesToString(sub.sid))
  3328			if acc != nil {
  3329				acc.sl.Remove(sub)
  3330			}
  3331		}
  3332	
  3333		// Check to see if we have shadow subscriptions.
  3334		var updateRoute bool
  3335		var isSpokeLeaf bool
  3336		shadowSubs := sub.shadow
  3337		sub.shadow = nil
  3338		if len(shadowSubs) > 0 {
  3339			isSpokeLeaf = c.isSpokeLeafNode()
  3340			updateRoute = !isSpokeLeaf && (c.kind == CLIENT || c.kind == SYSTEM || c.kind == LEAF) && c.srv != nil
  3341		}
  3342		sub.close()
  3343		c.mu.Unlock()
  3344	
  3345		// Process shadow subs if we have them.
  3346		for _, nsub := range shadowSubs {
  3347			if err := nsub.im.acc.sl.Remove(nsub); err != nil {
  3348				c.Debugf("Could not remove shadow import subscription for account %q", nsub.im.acc.Name)
  3349			}
  3350			if updateRoute {
  3351				c.srv.updateRemoteSubscription(nsub.im.acc, nsub, -1)
  3352			} else if isSpokeLeaf {
  3353				nsub.im.acc.updateLeafNodesEx(nsub, -1, true)
  3354			}
  3355		}
  3356	
  3357		// Now check to see if this was part of a respMap entry for service imports.
  3358		// We can skip subscriptions on reserved replies.
  3359		if acc != nil && !isReservedReply(sub.subject) {
  3360			acc.checkForReverseEntry(string(sub.subject), nil, true)
  3361		}
  3362	}
```

## Developer hypothesis
When a subscription with shadow subscriptions is removed, `unsubscribe()` also decides whether to propagate interest changes for those shadows to routes or leafnodes. Worth checking how this cleanup behaves for the subscriptions that JetStream creates on behalf of consumers.
