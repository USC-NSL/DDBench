# Verification: raft-rs #345

```bash
cd harness
cargo test test_read_when_quorum_becomes_less_bug -- --nocapture
```

- **FAIL (bug present):** The test panics with:
  ```
  BUG: ReadIndex request stuck after quorum shrank -- read_states is empty
  ```
  `read_states` is empty because `remove_node` does not re-evaluate pending ReadIndex requests against the new smaller quorum.

- **PASS (bug fixed):** The test passes. After removing node 2, the leader's `read_states` is non-empty because the fix adds a quorum recheck in `remove_node` that advances any pending reads whose existing acks now satisfy the reduced quorum.
