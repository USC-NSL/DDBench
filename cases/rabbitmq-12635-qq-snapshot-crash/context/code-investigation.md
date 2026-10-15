# Code Investigation

## What was searched
The symptom describes a quorum queue follower crashing with `badarg` in a list operation called with lists of different lengths, while handling effects shortly after it installed a snapshot and started delivering to a consumer. Read how `rabbit_fifo` builds the effects that deliver messages to consumers (`deps/rabbit/src/rabbit_fifo.erl`).

## What was found
```
$ cat -n deps/rabbit/src/rabbit_fifo.erl | sed -n '2009,2076p'
  2009	add_delivery_effects(Effects0, AccMap, _State)
  2010	  when map_size(AccMap) == 0 ->
  2011	    %% does this ever happen?
  2012	    Effects0;
  2013	add_delivery_effects(Effects0, AccMap, State) ->
  2014	     maps:fold(fun (C, DiskMsgs, Efs)
  2015	                     when is_list(DiskMsgs) ->
  2016	                       lists:foldl(
  2017	                         fun (Msgs, E) ->
  2018	                                 [delivery_effect(C, Msgs, State) | E]
  2019	                         end, Efs, chunk_disk_msgs(DiskMsgs, 0, [[]]))
  2020	               end, Effects0, AccMap).
  2021	
  2022	take_next_msg(#?STATE{returns = Returns0,
  2023	                      messages = Messages0,
  2024	                      ra_indexes = Indexes0
  2025	                     } = State) ->
  2026	    case lqueue:out(Returns0) of
  2027	        {{value, NextMsg}, Returns} ->
  2028	            {NextMsg, State#?STATE{returns = Returns}};
  2029	        {empty, _} ->
  2030	            case rabbit_fifo_q:out(Messages0) of
  2031	                empty ->
  2032	                    empty;
  2033	                {?MSG(RaftIdx, _) = Msg, Messages} ->
  2034	                    %% add index here
  2035	                    Indexes = rabbit_fifo_index:append(RaftIdx, Indexes0),
  2036	                    {Msg, State#?STATE{messages = Messages,
  2037	                                       ra_indexes = Indexes}}
  2038	            end
  2039	    end.
  2040	
  2041	get_next_msg(#?STATE{returns = Returns0,
  2042	                     messages = Messages0}) ->
  2043	    case lqueue:get(Returns0, empty) of
  2044	        empty ->
  2045	            rabbit_fifo_q:get(Messages0);
  2046	        Msg ->
  2047	            Msg
  2048	    end.
  2049	
  2050	delivery_effect(ConsumerKey, [{MsgId, ?MSG(Idx,  Header)}],
  2051	                #?STATE{msg_cache = {Idx, RawMsg}} = State) ->
  2052	    {CTag, CPid} = consumer_id(ConsumerKey, State),
  2053	    {send_msg, CPid, {delivery, CTag, [{MsgId, {Header, RawMsg}}]},
  2054	     ?DELIVERY_SEND_MSG_OPTS};
  2055	delivery_effect(ConsumerKey, Msgs, State) ->
  2056	    {CTag, CPid} = consumer_id(ConsumerKey, State),
  2057	    RaftIdxs = lists:foldr(fun ({_, ?MSG(I, _)}, Acc) ->
  2058	                                   [I | Acc]
  2059	                           end, [], Msgs),
  2060	    {log, RaftIdxs,
  2061	     fun(Log) ->
  2062	             DelMsgs = lists:zipwith(
  2063	                         fun (Cmd, {MsgId, ?MSG(_Idx,  Header)}) ->
  2064	                                 {MsgId, {Header, get_msg(Cmd)}}
  2065	                         end, Log, Msgs),
  2066	             [{send_msg, CPid, {delivery, CTag, DelMsgs},
  2067	               ?DELIVERY_SEND_MSG_OPTS}]
  2068	     end,
  2069	     {local, node(CPid)}}.
  2070	
  2071	reply_log_effect(RaftIdx, MsgId, Header, Ready, From) ->
  2072	    {log, [RaftIdx],
  2073	     fun ([Cmd]) ->
  2074	             [{reply, From, {wrap_reply,
  2075	                             {dequeue, {MsgId, {Header, get_msg(Cmd)}}, Ready}}}]
  2076	     end}.
```

## Developer hypothesis
Delivery effects ask Ra to read message bodies back from the log by Raft index when the effect is executed. Worth checking how these effects are produced and executed on a member that has just installed a snapshot from the leader.
