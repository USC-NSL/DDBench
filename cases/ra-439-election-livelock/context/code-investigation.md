# Code Investigation

## What was searched
The symptom describes a Ra cluster that keeps cycling through elections without ever producing a leader, even though a majority of members is up. Since Ra uses pre-vote, read how a member in the candidate state handles the election-related messages it receives from other members (`handle_candidate/2` in `src/ra_server.erl`).

## What was found
```
$ grep -n "^handle_candidate(" src/ra_server.erl
838:handle_candidate(#request_vote_result{term = Term, vote_granted = true},
859:handle_candidate(#request_vote_result{term = Term},
867:handle_candidate(#request_vote_result{vote_granted = false}, State) ->
869:handle_candidate(#append_entries_rpc{term = Term} = Msg,
873:handle_candidate(#append_entries_rpc{leader_id = LeaderId},
878:handle_candidate(#heartbeat_rpc{term = Term} = Msg,
882:handle_candidate(#heartbeat_rpc{leader_id = LeaderId}, State) ->
886:handle_candidate({_PeerId, #heartbeat_reply{term = Term}},
894:handle_candidate({_PeerId, #append_entries_reply{term = Term}},
903:handle_candidate(#request_vote_rpc{term = Term} = Msg,
911:handle_candidate(#pre_vote_rpc{term = Term} = Msg,
919:handle_candidate(#request_vote_rpc{}, State = #{current_term := Term}) ->
922:handle_candidate(#pre_vote_rpc{}, State) ->
925:handle_candidate(#request_vote_result{}, State) ->
928:handle_candidate(#pre_vote_result{}, State) ->
931:handle_candidate({ra_log_event, Evt}, State = #{log := Log0}) ->
935:handle_candidate(election_timeout, State) ->
937:handle_candidate({register_external_log_reader, Pid}, #{log := Log0} = State) ->
940:handle_candidate(force_member_change, State0) ->
942:handle_candidate(Msg, State) ->
```

```
$ cat -n src/ra_server.erl | sed -n '900,945p'
   900	          [LogId, CurTerm, Term]),
   901	    State = update_term_and_voted_for(Term, undefined, State0),
   902	    {follower, State, []};
   903	handle_candidate(#request_vote_rpc{term = Term} = Msg,
   904	                 #{current_term := CurTerm,
   905	                   cfg := #cfg{log_id = LogId}} = State0)
   906	  when Term > CurTerm ->
   907	    ?INFO("~ts: candidate request_vote_rpc with higher term received ~b -> ~b",
   908	          [LogId, CurTerm, Term]),
   909	    State = update_term_and_voted_for(Term, undefined, State0),
   910	    {follower, State, [{next_event, Msg}]};
   911	handle_candidate(#pre_vote_rpc{term = Term} = Msg,
   912	                 #{current_term := CurTerm,
   913	                   cfg := #cfg{log_id = LogId}} = State0)
   914	  when Term > CurTerm ->
   915	    ?INFO("~ts: candidate pre_vote_rpc with higher term received ~b -> ~b",
   916	          [LogId, CurTerm, Term]),
   917	    State = update_term_and_voted_for(Term, undefined, State0),
   918	    {follower, State, [{next_event, Msg}]};
   919	handle_candidate(#request_vote_rpc{}, State = #{current_term := Term}) ->
   920	    Reply = #request_vote_result{term = Term, vote_granted = false},
   921	    {candidate, State, [{reply, Reply}]};
   922	handle_candidate(#pre_vote_rpc{}, State) ->
   923	    %% just ignore pre_votes that aren't of a higher term
   924	    {candidate, State, []};
   925	handle_candidate(#request_vote_result{}, State) ->
   926	    %% handle to avoid logging as unhandled
   927	    {candidate, State, []};
   928	handle_candidate(#pre_vote_result{}, State) ->
   929	    %% handle to avoid logging as unhandled
   930	    {candidate, State, []};
   931	handle_candidate({ra_log_event, Evt}, State = #{log := Log0}) ->
   932	    % simply forward all other events to ra_log
   933	    {Log, Effects} = ra_log:handle_event(Evt, Log0),
   934	    {candidate, State#{log => Log}, Effects};
   935	handle_candidate(election_timeout, State) ->
   936	    call_for_election(candidate, State);
   937	handle_candidate({register_external_log_reader, Pid}, #{log := Log0} = State) ->
   938	    {Log, Effs} = ra_log:register_reader(Pid, Log0),
   939	    {candidate, State#{log => Log}, Effs};
   940	handle_candidate(force_member_change, State0) ->
   941	    {follower, State0#{votes => 0}, [{next_event, force_member_change}]};
   942	handle_candidate(Msg, State) ->
   943	    log_unhandled_msg(candidate, Msg, State),
   944	    {candidate, State, []}.
   945	
```

## Developer hypothesis
`handle_candidate/2` has dedicated clauses for vote and pre-vote traffic plus several catch-alls. Worth checking how a candidate's handling of pre-vote and vote messages from other members affects those members' ability to make election progress.
