# Reproduction Procedure

## Quick start

```bash
cd cases/ra-439-election-livelock/
./setup.sh    # clone rabbitmq/ra, checkout buggy commit, build + fetch test deps
./reproduce.sh  # inject test, run CT suite → PASS/FAIL
```

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

FAIL: Bug is present — candidate silently drops pre_vote_rpc instead of replying
```

## Expected output (bug fixed)

On the fixed commit, `handle_candidate/2` calls `process_pre_vote/3` which correctly compares log indices and returns a `#pre_vote_result{vote_granted=...}` reply:

```
1 ok

PASS: Bug is fixed
```
