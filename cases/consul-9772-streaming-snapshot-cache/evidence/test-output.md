# Test Output

Obtained by running `go test -v -run TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache -count=1 -timeout 60s ./agent/consul/stream/` against the buggy build.

## Output

```
=== RUN   TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache
=== RUN   TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache/start_a_subscription_and_unsub
=== RUN   TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache/resume_the_subscription
    event_publisher_test.go:491: 
        	Error Trace:	event_publisher_test.go:491
        	Error:      	Not equal: 
        	            	expected: stream.Event{Topic:999, Index:0x1, Payload:stream.simplePayload{key:"sub-key", value:"snapshot-event-payload", noReadPerm:false}}
        	            	actual  : stream.Event{Topic:999, Index:0x0, Payload:stream.newSnapshotToFollow{framingEvent:stream.framingEvent{}}}
        	            	
        	            	Diff:
        	            	--- Expected
        	            	+++ Actual
        	            	@@ -2,7 +2,6 @@
        	            	  Topic: (stream.intTopic) 999,
        	            	- Index: (uint64) 1,
        	            	- Payload: (stream.simplePayload) {
        	            	-  key: (string) (len=7) "sub-key",
        	            	-  value: (string) (len=22) "snapshot-event-payload",
        	            	-  noReadPerm: (bool) false
        	            	+ Index: (uint64) 0,
        	            	+ Payload: (stream.newSnapshotToFollow) {
        	            	+  framingEvent: (stream.framingEvent) {
        	            	+  }
        	            	  }
        	Test:       	TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache/resume_the_subscription
        	Messages:   	fresh subscriber (Index=0) should get snapshot data first, not a framing event
--- FAIL: TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache (0.00s)
    --- PASS: TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache/start_a_subscription_and_unsub (0.00s)
    --- FAIL: TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache/resume_the_subscription (0.00s)
FAIL
FAIL	github.com/hashicorp/consul/agent/consul/stream	0.006s
FAIL
```
