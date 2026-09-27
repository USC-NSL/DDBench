# Code Investigation

## What was searched
The symptom describes an election livelock where no leader can be elected despite a majority being alive. Investigated how the candidate state handles incoming `pre_vote_rpc` messages.

## What was found

### handle_candidate clauses for pre_vote_rpc (src/ra_server.erl:911-924)
```erlang
handle_candidate(#pre_vote_rpc{term = Term} = Msg,
                 #{current_term := CurTerm,
                   cfg := #cfg{log_id = LogId}} = State0)
  when Term > CurTerm ->
    ?INFO("~ts: candidate pre_vote_rpc with higher term received ~b -> ~b",
          [LogId, CurTerm, Term]),
    State = update_term_and_voted_for(Term, undefined, State0),
    {follower, State, [{next_event, Msg}]};

handle_candidate(#request_vote_rpc{}, State = #{current_term := Term}) ->
    Reply = #request_vote_result{term = Term, vote_granted = false},
    {candidate, State, [{reply, Reply}]};

handle_candidate(#pre_vote_rpc{}, State) ->
    %% just ignore pre_votes that aren't of a higher term
    {candidate, State, []};
```

### Contrast with how request_vote_rpc is handled (returns a reply)
```erlang
handle_candidate(#request_vote_rpc{}, State = #{current_term := Term}) ->
    Reply = #request_vote_result{term = Term, vote_granted = false},
    {candidate, State, [{reply, Reply}]};
```

### handle_candidate catch-all for pre_vote_result
```erlang
handle_candidate(#pre_vote_result{}, State) ->
    %% handle to avoid logging as unhandled
    {candidate, State, []};
```

## Developer hypothesis
The `handle_candidate` catch-all clause for `pre_vote_rpc` and its returned effects list.
