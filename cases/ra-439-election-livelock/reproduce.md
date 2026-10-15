# Reproduction Procedure

## Quick start

```bash
# from the repository root
./bench.sh setup ra-439-election-livelock      # case repository at the buggy commit, build + fetch test deps
./bench.sh reproduce ra-439-election-livelock  # inject test, run CT suite → PASS/FAIL
```

Inside `./bench.sh shell ra-439-election-livelock` (source at `/workspace/src`), the same oracle runs as `bash /bench/reproduce.sh`.

## What the reproduce script does

1. Resets `test/ra_server_SUITE.erl` to the buggy-commit state.
2. Injects a `candidate_receives_pre_vote/1` CT test case that directly exercises `ra_server:handle_candidate/2` with a `#pre_vote_rpc{}` message.
3. Runs `make ct CT_SUITES=ra_server CT_OPTS="-case candidate_receives_pre_vote"`.
4. Checks the CT output for pass/fail.

## Expected output (bug present)

On the buggy commit, the injected test triggers a `badmatch` exception in the CT runner because `handle_candidate/2` returns `{candidate, State, []}` (empty effects, no reply) but the test expects `{candidate, #{}, [{reply, #pre_vote_result{...}}]}`:

```
{error,{test_case_failed,
  {{badmatch,{candidate, #{...}, []}},
   [{ra_server_SUITE,candidate_receives_pre_vote,1,...}]}}}

FAIL: Bug is present — a candidate does not answer a same-term pre-vote request
```

## Expected output (bug fixed)

On the fixed commit, `handle_candidate/2` calls `process_pre_vote/3` which correctly compares log indices and returns a `#pre_vote_result{vote_granted=...}` reply:

```
1 ok

PASS: Bug is fixed — a candidate answers same-term pre-vote requests
```

## Oracle verdict

`./bench.sh reproduce ra-439-election-livelock` rebuilds the worktree and runs the oracle (`reproduce.sh`). The injected Common Test case is named `ddbench_oracle_candidate_pre_vote`; it calls `ra_server:handle_candidate/2` on a term-5 candidate with three `#pre_vote_rpc{}` messages and decides from Common Test's `suite.log`.

- **FAIL** (exit 1): the candidate does not reply `#pre_vote_result{vote_granted = true}` to a same-term pre-vote with an equal log index (e.g. it returns no reply), does not reply `vote_granted = false` to one with a lower log index, or does not become a term-6 follower on a term-6 pre-vote. A worktree that does not build, an oracle case that does not compile or is skipped, or a passing case while `make ct` exits non-zero, is also FAIL.
- **PASS** (exit 0): all three pre-votes get the expected response and `make ct` exits 0.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or `test/ra_server_SUITE.erl` is missing), the pristine suite cannot be read or lacks the injection anchors, or the case did not run and no compile error explains it.
