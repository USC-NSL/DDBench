# Code Investigation

## What was searched
The symptom describes a data race during leadership transfer. Investigated the `candidateFromLeadershipTransfer` field to determine its type and how it is accessed across goroutines.

## What was found
```
$ grep -n "candidateFromLeadershipTransfer" api.go raft.go

api.go:133:	// candidateFromLeadershipTransfer is used to indicate that this server became
api.go:137:	candidateFromLeadershipTransfer bool
raft.go:296:	defer func() { r.candidateFromLeadershipTransfer = false }()
raft.go:1393:	if a.Term > r.getCurrentTerm() || (r.getState() != Follower && !r.candidateFromLeadershipTransfer) {
raft.go:1975:	r.candidateFromLeadershipTransfer = true
```

The field is declared as a plain `bool` in api.go:137:
```go
candidateFromLeadershipTransfer bool
```

It is written in two places:
- raft.go:1975 — set to `true` before starting the candidate loop (called from the main goroutine via `liveBootstrap` or leadership transfer path)
- raft.go:296 — set to `false` via defer at the start of `runCandidate` (runs in the main goroutine)

It is read in:
- raft.go:1393 — inside `processHeartbeat` / `appendEntries` handler, which runs from an RPC goroutine handling incoming AppendEntries requests

## Developer hypothesis
The `candidateFromLeadershipTransfer` field and its access pattern across goroutines.
