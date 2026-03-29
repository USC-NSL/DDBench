# Solution: Ra #439

## Fix

- **PR:** https://github.com/rabbitmq/ra/pull/442
- **Commit:** `d128c812fbf582bbaffd0f94bc20a236d078fb6f`

## Fix locus

- **Component:** Candidate state message handler (`src/ra_server.erl`)
- **Files:**
  - `src/ra_server.erl` (+27/-3) — replaces the catch-all `handle_candidate(#pre_vote_rpc{}, State) -> {candidate, State, []}` with a call to `process_pre_vote(candidate, PreVote, State)`; adds the `process_pre_vote/3` function (handles both `Term >= CurTerm` and `Term < CurTerm` cases, checks log-index ordering via `is_candidate_log_up_to_date/3`, returns `#pre_vote_result{}` reply)
  - `test/ra_server_SUITE.erl` (+3/-0) — adds `candidate_receives_pre_vote` to `all()` and the test function

## Root cause

`handle_candidate/2` in `src/ra_server.erl` had a catch-all clause for `#pre_vote_rpc{}` messages that did not have a higher term:

```erlang
handle_candidate(#pre_vote_rpc{}, State) ->
    %% just ignore pre_votes that aren't of a higher term
    {candidate, State, []};
```

This was incorrect. When a candidate (which has already bumped its term) receives a `#pre_vote_rpc{}` from a peer in `pre_vote` state with the **same or lower term but a higher log index**, it silently drops the message — returns empty effects without sending a reply. The pre_vote sender never receives a response, so it cannot complete its pre_vote round and advance to candidate. The existing candidate cannot win the election either (because the pre_vote sender has a longer log and will not grant votes to a candidate with fewer entries). The cluster is stuck: no progress is made by either member, and if these are the only two members with running election timers, no leader is ever elected.

The root cause is that `process_pre_vote/3` — which correctly handles the log-index comparison and sends a `#pre_vote_result{}` reply — was called from `handle_follower/2` and `handle_pre_vote/2` but was **not wired into `handle_candidate/2`**. The candidate state was not treated as a valid source of pre_vote replies, even though a candidate should participate in pre_vote rounds from peers that have a comparable or fresher log.

## Diagnosis chain

1. **Runtime observation**: Ra cluster members cycle through `follower → pre_vote → candidate` without ever reaching `leader`. No error logs — pure liveness failure.
2. **Code path from symptom**: The livelock involves two specific members: one in `candidate` state (higher term), one in `pre_vote` state (higher log index). The candidate is not granting votes and the pre_vote member is not advancing.
3. **Narrowing to message handler**: The pre_vote member sends `#pre_vote_rpc{}` to the candidate. Inspecting `handle_candidate/2` reveals the catch-all: `handle_candidate(#pre_vote_rpc{}, State) -> {candidate, State, []}` — no reply is sent.
4. **Root cause confirmed**: The pre_vote sender receives no response from the candidate, stalling the pre_vote round. The candidate cannot win because the pre_vote member has a higher last_log_index (does not grant votes). Both are stuck.
5. **Fix**: Route `#pre_vote_rpc{}` in `handle_candidate/2` through `process_pre_vote(candidate, PreVote, State)`. This sends a `#pre_vote_result{vote_granted=...}` reply based on log-index comparison, breaking the deadlock.

## Fix description

The fix replaces the catch-all `handle_candidate(#pre_vote_rpc{}, State)` with a branch that calls `process_pre_vote(candidate, PreVote, State)`. The `process_pre_vote/3` function already existed and correctly handles pre_vote RPCs for follower and pre_vote states; the fix extends it to the candidate state as well.

When the candidate receives a `#pre_vote_rpc{}` with `Term >= CurTerm` and the peer's log is up-to-date (or equal), it replies `vote_granted=true`, allowing the pre_vote member to advance. When the peer's log is shorter, it replies `vote_granted=false`. In both cases, the reply unblocks the pre_vote round and the election can proceed.

## How to apply

```bash
git checkout d128c812fbf582bbaffd0f94bc20a236d078fb6f
```

## How to verify

Run `reproduce.sh` — should print `PASS: Bug is fixed`.
