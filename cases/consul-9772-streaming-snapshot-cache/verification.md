# Verification: Consul #9772

```bash
# Run the injected test that checks the snapshot cache is not polluted
# with framing events after a stale-index resume request.

cd agent/consul/stream
go test -run TestEventPublisher_SubscribeWithIndexNotZero_NewSnapshot_WithCache -v -count=1 -timeout 60s ./...
```

- **FAIL:** The injected test fails because the fresh subscriber (`Index=0`) receives a `newSnapshotToFollow` framing event from the cached snapshot. The cached snapshot incorrectly includes the framing event that was prepended for the stale-index subscriber.
- **PASS:** The test passes because the cached snapshot contains only data events. The `newSnapshotToFollow` framing event is prepended only for individual stale-index requests, separate from the cache.
