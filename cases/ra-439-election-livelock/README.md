# Ra #439: Election Livelock When Candidate Has Lower Log Index Than Pre-Vote Member

| Field | Value |
|-------|-------|
| Project | [Ra](https://github.com/rabbitmq/ra) (RabbitMQ's Raft library) |
| Issue | [#439](https://github.com/rabbitmq/ra/issues/439) |
| Fix PR | [#442](https://github.com/rabbitmq/ra/pull/442) |
| Language | Erlang |
| Category | Logic error (missing pre_vote_rpc handler in candidate state) |

## Bug Summary

When a Ra cluster member is in `candidate` state and receives a `#pre_vote_rpc{}` message from a peer that is in `pre_vote` state with a **higher log index**, the candidate silently ignores the message (returns empty effects, sends no reply). This creates an election livelock: the candidate cannot win the election because the pre_vote member has a fresher log and won't grant votes, but the pre_vote member cannot progress to candidate because the candidate ignores its pre_vote RPCs. Neither member can become leader, so the cluster stalls indefinitely even though a majority of members are alive.

The fix adds a branch to `handle_candidate/2` for `#pre_vote_rpc{}` that calls `process_pre_vote/3`, which correctly compares log indices and returns a `#pre_vote_result{}` reply — allowing the pre_vote member to either advance its election or be declined, breaking the deadlock.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## What to Expect

**When the bug is present (FAIL):**
The injected CT test fails with a `badmatch` exception: `handle_candidate/2` returns `{candidate, State, []}` but the test expects a `{reply, #pre_vote_result{...}}` effect.

**When the bug is fixed (PASS):**
`handle_candidate/2` calls `process_pre_vote/3`, which correctly replies with `#pre_vote_result{vote_granted=true|false}` based on log-index comparison.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable cluster behavior and liveness failure
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
