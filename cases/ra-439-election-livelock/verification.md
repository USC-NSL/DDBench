# Verification Criteria

## FAIL (bug present)

`reproduce.sh` exits with code 1 and prints:

```
FAIL: Bug is present — candidate silently drops pre_vote_rpc instead of replying
```

The CT test fails with a `badmatch` exception because `ra_server:handle_candidate/2` returns `{candidate, State, []}` (empty effects) when it receives a `#pre_vote_rpc{}` with the same term, but the test expects a `{reply, #pre_vote_result{...}}` effect.

## PASS (bug fixed)

`reproduce.sh` exits with code 0 and prints:

```
PASS: Bug is fixed
```

The CT test passes: `handle_candidate/2` delegates to `process_pre_vote/3` which checks log-index ordering and returns the correct `#pre_vote_result{vote_granted=true|false}` reply.

## Verification invariant

The oracle checks three scenarios in sequence:
1. Pre_vote_rpc with equal log index → `vote_granted=true` (candidate grants vote)
2. Pre_vote_rpc with lower log index → `vote_granted=false` (candidate declines)
3. Pre_vote_rpc with higher term → candidate transitions to `follower`

On the buggy commit, scenario 1 fails immediately (no reply produced). On the fixed commit, all three pass.
