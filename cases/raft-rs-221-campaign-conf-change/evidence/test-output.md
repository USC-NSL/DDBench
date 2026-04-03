# Test Output

Obtained by running `cargo test test_conf_change_check_before_campaign -- --nocapture` against the buggy build.

## Output

```
running 1 test

thread 'integration_cases::test_raft::test_conf_change_check_before_campaign' (44) panicked at tests/integration_cases/test_raft.rs:4093:5:
assertion `left == right` failed
  left: Follower
 right: Leader
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
test integration_cases::test_raft::test_conf_change_check_before_campaign ... FAILED

failures:

failures:
    integration_cases::test_raft::test_conf_change_check_before_campaign

test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 152 filtered out; finished in 0.01s

error: test failed, to rerun pass `--test tests`
```
