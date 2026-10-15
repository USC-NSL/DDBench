# Code Investigation

## What was searched
The symptom describes a consumer whose `FilterSubjects` match every subject in the stream delivering more than 20% slower than a consumer with no filter. Looked at how a consumer's filter configuration is turned into the data used when loading the next message (`o.subjf`, `o.filters`) and how `getNextMsg()` uses it.

## What was found
```
$ grep -n "o.filters" server/consumer.go
1225:		o.filters = gsl.NewSublist[struct{}]()
1227:			o.filters.Insert(filter, struct{}{})
1231:		o.filters = nil
2446:			o.filters = nil
2450:				o.filters = nil
2452:				o.filters = gsl.NewSublist[struct{}]()
2454:					o.filters.Insert(filter.subject, struct{}{})
4617:	filters, subjf, fseq := o.filters, o.subjf, o.sseq
4621:	} else if len(subjf) > 0 { // Means single filtered subject since o.filters means > 1.
5326:	filters, subjf := o.filters, o.subjf
6595:	filters, subjf, filter := o.filters, o.subjf, _EMPTY_
```

```
$ cat -n server/consumer.go | sed -n '1213,1232p'
  1213		for _, filter := range gatherSubjectFilters(o.cfg.FilterSubject, o.cfg.FilterSubjects) {
  1214			sub := &subjectFilter{
  1215				subject:          filter,
  1216				hasWildcard:      subjectHasWildcard(filter),
  1217				tokenizedSubject: tokenizeSubjectIntoSlice(nil, filter),
  1218			}
  1219			o.subjf = append(o.subjf, sub)
  1220		}
  1221	
  1222		// If we have multiple filter subjects, create a sublist which we will use
  1223		// in calling store.LoadNextMsgMulti.
  1224		if len(o.cfg.FilterSubjects) > 0 {
  1225			o.filters = gsl.NewSublist[struct{}]()
  1226			for _, filter := range o.cfg.FilterSubjects {
  1227				o.filters.Insert(filter, struct{}{})
  1228			}
  1229		} else {
  1230			// Make sure this is nil otherwise.
  1231			o.filters = nil
  1232		}
```

```
$ cat -n server/consumer.go | sed -n '4611,4641p'
  4611		var sseq uint64
  4612		var err error
  4613		var sm *StoreMsg
  4614		var pmsg = getJSPubMsgFromPool()
  4615	
  4616		// Grab next message applicable to us.
  4617		filters, subjf, fseq := o.filters, o.subjf, o.sseq
  4618		// Check if we are multi-filtered or not.
  4619		if filters != nil {
  4620			sm, sseq, err = o.mset.store.LoadNextMsgMulti(filters, fseq, &pmsg.StoreMsg)
  4621		} else if len(subjf) > 0 { // Means single filtered subject since o.filters means > 1.
  4622			filter, wc := subjf[0].subject, subjf[0].hasWildcard
  4623			sm, sseq, err = o.mset.store.LoadNextMsg(filter, wc, fseq, &pmsg.StoreMsg)
  4624		} else {
  4625			// No filter here.
  4626			sm, sseq, err = o.mset.store.LoadNextMsg(_EMPTY_, false, fseq, &pmsg.StoreMsg)
  4627		}
  4628		if sm == nil {
  4629			pmsg.returnToPool()
  4630			pmsg = nil
  4631		}
  4632		// Check if we should move our o.sseq.
  4633		if sseq >= o.sseq {
  4634			// If we are moving step by step then sseq == o.sseq.
  4635			// If we have jumped we should update skipped for other replicas.
  4636			if sseq != o.sseq && err == ErrStoreEOF {
  4637				o.updateSkipped(sseq + 1)
  4638			}
  4639			o.sseq = sseq + 1
  4640		}
  4641		return pmsg, 1, err
```

## Developer hypothesis
The per-message lookup in `getNextMsg()` depends on how the filters were prepared when the consumer was created or updated. Worth checking how filter configurations that end up covering every subject of the stream are handled on that path.
