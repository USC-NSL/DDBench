# Reproduce: PROJECT #ISSUE

All commands run inside `./bench.sh shell CASE_NAME`, from the worktree `/workspace/src`.

## Step 1: Start the service
```bash
TODO: startup command
```

## Step 2: Trigger the bug
```bash
TODO: commands that trigger the bug
```

## Expected result (bug present)
TODO: What happens when the bug is triggered (crash, wrong output, hang).

## Oracle verdict

`./bench.sh reproduce CASE_NAME` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): TODO: what the oracle observes when the bug is present (crash, wrong output, timeout). A worktree that does not build, or TODO: the code under test that does not start, is also FAIL.
- **PASS** (exit 0): TODO: what the oracle requires once the bug is fixed (process survives, test passes, correct output).
- **ERROR** (exit 2): TODO: when the oracle's own machinery cannot decide (trigger not established, harness file missing).
