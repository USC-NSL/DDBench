# Code Investigation

## What was searched
The symptom describes a delete of a sequence past the end of an R3 stream leaving the stream inaccessible for several seconds, with the cluster state being reset. Searched for where the clustered stream code decides to reset its state, and read how committed delete operations are applied in `applyStreamEntries()` (`server/jetstream_cluster.go`).

## What was found
```
$ grep -n "isClusterResetErr\|resetClusteredState(" server/jetstream_cluster.go
2478:					if isClusterResetErr(err) {
2484:						if mset.resetClusteredState(err) {
2828:func (mset *stream) resetClusteredState(err error) bool {
3045:					if isClusterResetErr(err) || isOutOfSpaceErr(err) || err == errStreamClosed {
3160:					mset.resetClusteredState(err)
```

```
$ cat -n server/jetstream_cluster.go | sed -n '3044,3097p'
  3044						// Only return in place if we are going to reset our stream or we are out of space, or we are closed.
  3045						if isClusterResetErr(err) || isOutOfSpaceErr(err) || err == errStreamClosed {
  3046							return err
  3047						}
  3048						s.Debugf("Apply stream entries for '%s > %s' got error processing message: %v",
  3049							mset.account(), mset.name(), err)
  3050					}
  3051	
  3052				case deleteMsgOp:
  3053					md, err := decodeMsgDelete(buf[1:])
  3054					if err != nil {
  3055						if node := mset.raftNode(); node != nil {
  3056							s := js.srv
  3057							s.Errorf("JetStream cluster could not decode delete msg for '%s > %s' [%s]",
  3058								mset.account(), mset.name(), node.Group())
  3059						}
  3060						panic(err.Error())
  3061					}
  3062					s, cc := js.server(), js.cluster
  3063	
  3064					var removed bool
  3065					if md.NoErase {
  3066						removed, err = mset.removeMsg(md.Seq)
  3067					} else {
  3068						removed, err = mset.eraseMsg(md.Seq)
  3069					}
  3070	
  3071					// Cluster reset error.
  3072					if err == ErrStoreEOF {
  3073						return err
  3074					}
  3075	
  3076					if err != nil && !isRecovering {
  3077						s.Debugf("JetStream cluster failed to delete stream msg %d from '%s > %s': %v",
  3078							md.Seq, md.Client.serviceAccount(), md.Stream, err)
  3079					}
  3080	
  3081					js.mu.RLock()
  3082					isLeader := cc.isStreamLeader(md.Client.serviceAccount(), md.Stream)
  3083					js.mu.RUnlock()
  3084	
  3085					if isLeader && !isRecovering {
  3086						var resp = JSApiMsgDeleteResponse{ApiResponse: ApiResponse{Type: JSApiMsgDeleteResponseType}}
  3087						if err != nil {
  3088							resp.Error = NewJSStreamMsgDeleteFailedError(err, Unless(err))
  3089							s.sendAPIErrResponse(md.Client, mset.account(), md.Subject, md.Reply, _EMPTY_, s.jsonResponse(resp))
  3090						} else if !removed {
  3091							resp.Error = NewJSSequenceNotFoundError(md.Seq)
  3092							s.sendAPIErrResponse(md.Client, mset.account(), md.Subject, md.Reply, _EMPTY_, s.jsonResponse(resp))
  3093						} else {
  3094							resp.Success = true
  3095							s.sendAPIResponse(md.Client, mset.account(), md.Subject, md.Reply, _EMPTY_, s.jsonResponse(resp))
  3096						}
  3097					}
```

```
$ grep -n -A2 "func isClusterResetErr" server/store.go
746:func isClusterResetErr(err error) bool {
747-	return err == errLastSeqMismatch || err == ErrStoreEOF || err == errFirstSequenceMismatch || errors.Is(err, errCatchupAbortedNoLeader) || err == errCatchupTooManyRetries
748-}
```

## Developer hypothesis
Errors returned from applying committed entries can trigger a reset of the stream's clustered state. Worth checking how errors from the individual entry handlers in `applyStreamEntries()` are surfaced and classified, and whether that matches what each operation needs.
