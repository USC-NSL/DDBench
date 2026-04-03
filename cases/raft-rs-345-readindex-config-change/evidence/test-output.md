# Test Output

Obtained by running `cargo test test_read_when_quorum_becomes_less_bug -- --nocapture` in the `harness` directory against the buggy build.

## Output

```
running 1 test

thread 'integration_cases::test_raft::test_read_when_quorum_becomes_less_bug' (46) panicked at harness/tests/integration_cases/test_raft.rs:4971:5:
BUG: ReadIndex request stuck after quorum shrank — read_states is empty
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
test integration_cases::test_raft::test_read_when_quorum_becomes_less_bug ... FAILED

failures:

failures:
    integration_cases::test_raft::test_read_when_quorum_becomes_less_bug

test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 173 filtered out; finished in 0.01s

error: test failed, to rerun pass `--test tests`
```
