# Symptom

Under sustained Kafka client load, when authentication failures occur, Redpanda crashes with a Seastar future assertion error:

```
FATAL: Exceptional future ignored: ...
```

or

```
seastar::broken_promise (broken promise)
```

The crash occurs because when `do_authenticate` fails for a Kafka client connection, the broker connection handler does not properly stop the broker before exiting. This leaves dangling futures that reference destroyed objects. When those futures eventually try to complete, they trigger Seastar's assert for unhandled exceptional futures.

The issue is non-deterministic and requires sustained load to hit consistently. A single authentication failure may not trigger it, but repeated failures under load will eventually cause the assert.
