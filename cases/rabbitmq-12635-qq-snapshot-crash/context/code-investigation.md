# Code Investigation

## What was searched
The symptom describes a `badarg` error in a list operation after snapshot installation. Investigated `delivery_effect` and `reply_log_effect` in `rabbit_fifo.erl` for list length mismatches.

## What was found

### delivery_effect (deps/rabbit/src/rabbit_fifo.erl:2050-2070)
```erlang
delivery_effect(ConsumerKey, [{MsgId, ?MSG(Idx,  Header)}],
                #?STATE{msg_cache = {Idx, RawMsg}} = State) ->
    {CTag, CPid} = consumer_id(ConsumerKey, State),
    {send_msg, CPid, {delivery, CTag, [{MsgId, {Header, RawMsg}}]},
     ?DELIVERY_SEND_MSG_OPTS};
delivery_effect(ConsumerKey, Msgs, State) ->
    {CTag, CPid} = consumer_id(ConsumerKey, State),
    RaftIdxs = lists:foldr(fun ({_, ?MSG(I, _)}, Acc) ->
                                   [I | Acc]
                           end, [], Msgs),
    {log, RaftIdxs,
     fun(Log) ->
             DelMsgs = lists:zipwith(
                         fun (Cmd, {MsgId, ?MSG(_Idx,  Header)}) ->
                                 {MsgId, {Header, get_msg(Cmd)}}
                         end, Log, Msgs),
             [{send_msg, CPid, {delivery, CTag, DelMsgs},
               ?DELIVERY_SEND_MSG_OPTS}]
     end,
     {local, node(CPid)}}.
```

### reply_log_effect (deps/rabbit/src/rabbit_fifo.erl:2071-2077)
```erlang
reply_log_effect(RaftIdx, MsgId, Header, Ready, From) ->
    {log, [RaftIdx],
     fun ([Cmd]) ->
             [{reply, From, {wrap_reply,
                             {dequeue, {MsgId, {Header, get_msg(Cmd)}}, Ready}}}]
     end}.
```

## Developer hypothesis
The `lists:zipwith/3` call in `delivery_effect` and the relationship between its `Log` and `Msgs` arguments.
