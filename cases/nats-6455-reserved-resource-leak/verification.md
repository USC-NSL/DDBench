# Verification: NATS Server #6455

Run the injected Go test to verify:

```bash
cd /workspace/worktrees/nats-6455-reserved-resource-leak  # or $WORK_DIR
go test -v -run "^TestJetStreamClusterReservedResourcesAccountingAfterClusterReset$" -count=1 -timeout 120s ./server/ 2>&1 | tail -30
```

## Expected results

**FAIL (bug present):**
The test fails because after `resetClusteredState()`, the reserved store bytes equal `2 * maxBytes` instead of `maxBytes`. The assertion `require_Equal(t, store, maxBytes)` fails with output like:
```
--- FAIL: TestJetStreamClusterReservedResourcesAccountingAfterClusterReset
    --- FAIL: TestJetStreamClusterReservedResourcesAccountingAfterClusterReset/last_sequence_mismatch
        require_Equal: 2147483648 != 1073741824
```

**PASS (bug fixed):**
The test passes -- reserved store bytes remain exactly `maxBytes` after the cluster state reset.
```
--- PASS: TestJetStreamClusterReservedResourcesAccountingAfterClusterReset/last_sequence_mismatch
--- PASS: TestJetStreamClusterReservedResourcesAccountingAfterClusterReset/first_sequence_mismatch
PASS
```

- **FAIL:** Reserved bytes grow by `maxBytes` on each reset (double-counted).
- **PASS:** Reserved bytes remain stable at `maxBytes` after reset.
