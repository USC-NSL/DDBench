# Symptom

A NATS JetStream server with clustered R3 streams progressively reports growing reserved disk usage until it claims the disk is full, even though no new streams are being created.

Server logs show a tight loop of:
```
Error applying entries to '[STREAM_NAME]': last sequence mismatch
Resetting stream cluster state for '[STREAM_NAME]'
```

Each reset cycle causes the stream's `MaxBytes` to be double-counted in the server's reserved resource accounting. After enough reset iterations, the reserved bytes exceed actual capacity and the server refuses to create new streams, reporting disk full.

Setting the affected stream to R1, restarting the servers, and returning it to R3 temporarily resolves the issue because the R1 transition releases and re-reserves resources exactly once.

## Observable indicators

- `JetStreamReservedResources()` returns `storeReserved` that is a multiple of the stream's `MaxBytes` (e.g., 2x, 3x, or more after repeated resets)
- Server eventually refuses new stream creation with resource-exceeded errors
- The leak accumulates on every call to `resetClusteredState()` triggered by `errLastSeqMismatch` or `errFirstSequenceMismatch`
