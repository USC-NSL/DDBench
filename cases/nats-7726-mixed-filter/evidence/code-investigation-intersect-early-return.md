# Code Investigation

## What was searched
The symptom describes a consumer with mixed wildcard and literal filter subjects (e.g., `events.*` and `events.specific`) failing to deliver messages to the literal subject. Investigated the subject tree intersection logic used for multi-filter consumers.

## What was found
```
$ sed -n "1738,1800p" server/sublist.go   # intersectStree function
func intersectStree[T any](st *stree.SubjectTree[T], r *level, subj []byte, cb func(subj []byte, entry *T)) {
	nsubj := subj
	if len(nsubj) > 0 {
		nsubj = append(subj, '.')
	}
	if r.fwc != nil {
		nsubj := append(nsubj, '>')
		st.Match(nsubj, cb)
		return
	}
	if r.pwc != nil {
		var done bool
		nsubj := append(nsubj, '*')
		if len(r.pwc.psubs)+len(r.pwc.qsubs) > 0 {
			st.Match(nsubj, cb)
			done = true                          // <--- marks done when pwc has subscriptions
		}
		if r.pwc.next.numNodes() > 0 {
			intersectStree(st, r.pwc.next, nsubj, cb)
		}
		if done {
			return                               // <--- RETURNS HERE, skipping literal nodes below
		}
	}
	// Normal node with subject literals, keep iterating.
	for t, n := range r.nodes {                  // <--- literal nodes never reached when done==true
		if r.pwc != nil && r.pwc.next.numNodes() > 0 && n.next.numNodes() > 0 {
			continue
		}
		nsubj := append(nsubj, t...)
		if len(n.psubs)+len(n.qsubs) > 0 {
			if subjectHasWildcard(bytesToString(nsubj)) {
				st.Match(nsubj, cb)
			} else {
				if e, ok := st.Find(nsubj); ok {
					cb(nsubj, e)
				}
			}
		}
		if n.next.numNodes() > 0 {
			intersectStree(st, n.next, nsubj, cb)
		}
	}
}
```

The subscription list stores filter subjects in a tree structure. A consumer with filters `events.*` (wildcard) and `events.specific` (literal) creates both a `pwc` node and a literal node at the `events.` level.

When `intersectStree` processes this level:
1. It finds `r.pwc != nil` (from `events.*`)
2. The pwc node has subscriptions (`len(r.pwc.psubs) > 0`), so it calls `st.Match(nsubj, cb)` and sets `done = true`
3. After processing the pwc's children, it checks `if done { return }` — and exits
4. The `for t, n := range r.nodes` loop (which would process the literal `events.specific`) is never reached

## Developer hypothesis
The `intersectStree` function's handling of `pwc` nodes alongside literal nodes at the same tree level.
