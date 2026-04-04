# Code Investigation

## What was searched
The symptom describes ~20% performance degradation when a consumer uses `FilterSubjects` that match all stream subjects, compared to no filter at all. Investigated the code path selection in `getNextMsg` and how `o.filters` is initialized.

## What was found
```
$ sed -n "1222,1232p" server/consumer.go   # filter setup during consumer creation
	// If we have multiple filter subjects, create a sublist which we will use
	// in calling store.LoadNextMsgMulti.
	if len(o.cfg.FilterSubjects) > 0 {
		o.filters = gsl.NewSublist[struct{}]()
		for _, filter := range o.cfg.FilterSubjects {
			o.filters.Insert(filter, struct{}{})
		}
	} else {
		// Make sure this is nil otherwise.
		o.filters = nil
	}

$ sed -n "4616,4627p" server/consumer.go   # getNextMsg path selection
	// Grab next message applicable to us.
	filters, subjf, fseq := o.filters, o.subjf, o.sseq
	// Check if we are multi-filtered or not.
	if filters != nil {
		sm, sseq, err = o.mset.store.LoadNextMsgMulti(filters, fseq, &pmsg.StoreMsg)
	} else if len(subjf) > 0 { // Means single filtered subject since o.filters means > 1.
		filter, wc := subjf[0].subject, subjf[0].hasWildcard
		sm, sseq, err = o.mset.store.LoadNextMsg(filter, wc, fseq, &pmsg.StoreMsg)
	} else {
		// No filter here.
		sm, sseq, err = o.mset.store.LoadNextMsg(_EMPTY_, false, fseq, &pmsg.StoreMsg)
	}

$ sed -n "3525,3570p" server/consumer.go   # isFiltered function
func (o *consumer) isFiltered() bool {
	...
	if len(msetSubjects) == 1 && len(o.subjf) == 1 {
		return msetSubjects[0] != o.subjf[0].subject
	}
	if len(msetSubjects) != len(o.subjf) {
		return true
	}
	// expensive check: all stream subjects match all consumer filters
	cfilters := make(map[string]struct{}, len(o.subjf))
	for _, val := range o.subjf {
		cfilters[val.subject] = struct{}{}
	}
	for _, val := range msetSubjects {
		if _, ok := cfilters[val]; !ok {
			return true
		}
	}
	return false  // filter matches everything → not filtered
}
```

The three message-loading paths in order of performance (fastest to slowest):
1. **No filter** (`filters == nil && len(subjf) == 0`): `LoadNextMsg(_EMPTY_, false, ...)` — sequential scan, no filtering overhead
2. **Single filter** (`filters == nil && len(subjf) > 0`): `LoadNextMsg(filter, wc, ...)` — targeted lookup
3. **Multi filter** (`filters != nil`): `LoadNextMsgMulti(filters, ...)` — sublist intersection, most overhead

The issue: `o.filters` is set whenever `len(o.cfg.FilterSubjects) > 0` (line 1224), even for a single entry. The code does NOT check whether the filter actually narrows the result set. So a consumer with `FilterSubjects: ["events.>"]` on a stream with subject `"events.>"` creates `o.filters`, forcing every message through `LoadNextMsgMulti` — the slowest path.

Meanwhile, `isFiltered()` correctly detects that the filter matches all stream subjects and returns `false`. But this function is used elsewhere (e.g., `needAck`, `streamNumPending`) and NOT consulted in `getNextMsg` for path selection. The `getNextMsg` function only checks `filters != nil`.

## Developer hypothesis
The `o.filters` initialization in consumer creation and the message-loading path selection in `getNextMsg`, relative to where `isFiltered()` is consulted.
