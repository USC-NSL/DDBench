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
# from the repository root
./bench.sh setup ra-439-election-livelock        # build image + case repository, warm caches
./bench.sh reproduce ra-439-election-livelock    # FAIL (exit 1) while the bug is present
./bench.sh shell ra-439-election-livelock        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/ra` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The injected CT test fails with a `badmatch` exception: `handle_candidate/2` returns `{candidate, State, []}` but the test expects a `{reply, #pre_vote_result{...}}` effect.

**When the bug is fixed (PASS):**
`handle_candidate/2` calls `process_pre_vote/3`, which correctly replies with `#pre_vote_result{vote_granted=true|false}` based on log-index comparison.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable cluster behavior and liveness failure
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
