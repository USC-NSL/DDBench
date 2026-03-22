# Symptom: etcd #20704

The `client/v3/leasing` cache has multiple linearizability bugs. The cache promises linearizable reads but violates this guarantee under concurrent modifications:

1. **Delete + Put race:** A key is deleted on the etcd servers, but future `Get` calls through the leasing cache return a value for the deleted key.
2. **Put + Get race:** A `Get` returns a stale value instead of the latest `Put` value.
3. **Put + Put + Get race:** A `Get` returns a `Version` field value that does not correspond to any actual revision of the key.

These are correctness bugs that break the linearizability contract of the leasing cache.
