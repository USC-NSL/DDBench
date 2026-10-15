# Code Investigation

## What was searched

The consumer reports one unprocessed message but a fetch times out, and only when its filter set mixes wildcard and literal subjects. Searched for how the stores find the stored subjects that match a set of filter subjects. All matches lead to `stree.IntersectGSL`.

## What was found

```
$ grep -n "IntersectGSL" server/*.go server/stree/*.go | grep -v _test.go
server/filestore.go:2659:		stree.IntersectGSL(mb.fss, sl, func(subj []byte, ss *SimpleState) {
server/filestore.go:2911:		stree.IntersectGSL(mb.fss, sl, func(subj []byte, ss *SimpleState) {
server/filestore.go:4008:		stree.IntersectGSL(fs.psim, sl, func(subj []byte, psi *psi) {
server/filestore.go:4107:			stree.IntersectGSL[SimpleState](mb.fss, sl, func(bsubj []byte, ss *SimpleState) {
server/filestore.go:4170:	stree.IntersectGSL(fs.psim, sl, func(subj []byte, psi *psi) {
server/filestore.go:4221:				stree.IntersectGSL(mb.fss, sl, func(bsubj []byte, ss *SimpleState) {
server/memstore.go:916:	stree.IntersectGSL[SimpleState](ms.fss, sl, func(subj []byte, fss *SimpleState) {
server/stree/stree.go:455:// IntersectGSL will match all items in the given subject tree that
server/stree/stree.go:458:func IntersectGSL[T any, SL comparable](t *SubjectTree[T], sl *gsl.GenericSublist[SL], cb func(subject []byte, val *T)) {
```

```
$ cat -n server/stree/stree.go | sed -n "452,510p"
   452		}
   453	}
   454	
   455	// IntersectGSL will match all items in the given subject tree that
   456	// have interest expressed in the given sublist. The callback will only be called
   457	// once for each subject, regardless of overlapping subscriptions in the sublist.
   458	func IntersectGSL[T any, SL comparable](t *SubjectTree[T], sl *gsl.GenericSublist[SL], cb func(subject []byte, val *T)) {
   459		if t == nil || t.root == nil || sl == nil {
   460			return
   461		}
   462		var _pre [256]byte
   463		_intersectGSL(t.root, _pre[:0], sl, cb)
   464	}
   465	
   466	func _intersectGSL[T any, SL comparable](n node, pre []byte, sl *gsl.GenericSublist[SL], cb func(subject []byte, val *T)) {
   467		if n.isLeaf() {
   468			ln := n.(*leaf[T])
   469			subj := append(pre, ln.suffix...)
   470			if sl.HasInterest(bytesToString(subj)) {
   471				cb(subj, &ln.value)
   472			}
   473			return
   474		}
   475		bn := n.base()
   476		pre = append(pre, bn.prefix...)
   477		for _, cn := range n.children() {
   478			if cn == nil {
   479				continue
   480			}
   481			subj := append(pre, cn.path()...)
   482			if !hasInterestForTokens(sl, subj, len(pre)) {
   483				continue
   484			}
   485			_intersectGSL(cn, pre, sl, cb)
   486		}
   487	}
   488	
   489	// The subject tree can return partial tokens so we need to check starting interest
   490	// only from whole tokens when we encounter a tsep.
   491	func hasInterestForTokens[SL comparable](sl *gsl.GenericSublist[SL], subj []byte, since int) bool {
   492		for i := since; i < len(subj); i++ {
   493			if subj[i] == tsep {
   494				if !sl.HasInterestStartingIn(bytesToString(subj[:i])) {
   495					return false
   496				}
   497			}
   498		}
   499		return true
   500	}
   501	
   502	// Note this will avoid a copy of the data used for the string, but it will also reference the existing slice's data pointer.
   503	// So this should be used sparingly when we know the encompassing byte slice's lifetime is the same.
   504	func bytesToString(b []byte) string {
   505		if len(b) == 0 {
   506			return ""
   507		}
   508		p := unsafe.SliceData(b)
   509		return unsafe.String(p, len(b))
   510	}
```

## Developer hypothesis

Which stored subjects a multi-filter consumer can see depends on this walk, which skips whole branches of the subject tree based on what the filter sublist reports for partial subjects. It is worth checking what that pruning does with this consumer's mix of filters.
