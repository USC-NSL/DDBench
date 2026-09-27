# Code Investigation

## What was searched
The symptom describes subscription leaks when using overlapping stream imports with rapidly created/destroyed consumers. Investigated how shadow subscriptions (created for stream imports) are cleaned up when a JETSTREAM-kind internal client unsubscribes.

## What was found
```
$ sed -n "3025,3040p" server/client.go   # processSub creates shadow subs for ALL client kinds
	if err := c.addShadowSubscriptions(acc, sub); err != nil {
		c.Errorf(err.Error())
	}
	...
	// If we are routing and this is a local sub, add to the route map for the associated account.
	if kind == CLIENT || kind == SYSTEM || kind == JETSTREAM || kind == ACCOUNT {
		srv.updateRouteSubscriptionMap(acc, sub, 1)   // <--- JETSTREAM included, count incremented
```

Shadow subs are created and the route subscription map is incremented (+1) for JETSTREAM clients.

```
$ sed -n "3333,3355p" server/client.go   # unsubscribe cleanup for shadow subs
	shadowSubs := sub.shadow
	sub.shadow = nil
	if len(shadowSubs) > 0 {
		isSpokeLeaf = c.isSpokeLeafNode()
		updateRoute = !isSpokeLeaf && (c.kind == CLIENT || c.kind == SYSTEM || c.kind == LEAF) && c.srv != nil
		                                                                          ^^^^ JETSTREAM NOT listed
	}
	sub.close()
	c.mu.Unlock()

	// Process shadow subs if we have them.
	for _, nsub := range shadowSubs {
		if err := nsub.im.acc.sl.Remove(nsub); err != nil {
			c.Debugf("Could not remove shadow import subscription for account %q", nsub.im.acc.Name)
		}
		if updateRoute {                          // <--- always false for JETSTREAM clients
			c.srv.updateRemoteSubscription(nsub.im.acc, nsub, -1)   // never called
		} else if isSpokeLeaf {
			nsub.im.acc.updateLeafNodesEx(nsub, -1, true)
		}
	}
```

On subscribe (processSub, line ~3035): JETSTREAM is included in the route map update (+1).
On unsubscribe (line ~3340): JETSTREAM is NOT included in the `updateRoute` condition, so the route map is never decremented (-1).

## Developer hypothesis
The subscribe and unsubscribe paths' respective handling of client kinds for route map updates.
