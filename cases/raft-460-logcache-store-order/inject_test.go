package raft

import (
	"errors"
	"strings"
	"sync"
	"testing"
)

// injectErrorStore wraps a LogStore and injects failures into StoreLogs.
// After injectFailNext(n) is called, the next n StoreLogs calls return an error.
// Named with "inject" prefix to avoid conflict with errorStore in log_cache_test.go
// which is added by the fix commit (PR #460).
type injectErrorStore struct {
	LogStore
	mu      sync.Mutex
	fail    bool
	failed  int
	failMax int
}

func (e *injectErrorStore) StoreLogs(logs []*Log) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.fail {
		e.failed++
		if e.failed <= e.failMax {
			return errors.New("injected store error")
		}
		e.fail = false
	}
	return e.LogStore.StoreLogs(logs)
}

func (e *injectErrorStore) injectFailNext(count int) {
	e.mu.Lock()
	e.fail = true
	e.failed = 0
	e.failMax = count
	e.mu.Unlock()
}

// TestLogCacheStaleDataOnStoreError verifies that LogCache does NOT cache
// log entries when the underlying LogStore.StoreLogs() fails.
//
// Bug (hashicorp/raft#429, PR #460): LogCache.StoreLogs() inserts entries
// into the in-memory ring buffer BEFORE calling the backend store's
// StoreLogs(). If the backend fails, the cache contains entries that were
// never persisted. A subsequent GetLog() returns the cached (but
// unpersisted) entry, giving the caller a false belief that the entry is
// durable. On node restart the cache is gone and the entry is missing from
// the backend store, causing a "log not found" panic in NewRaft().
//
// Detection strategy:
//   - Create a LogCache wrapping an injectErrorStore that will fail once
//   - Pre-populate the backend with 4 log entries (index 1..4)
//   - Attempt to store log entry at index 5 via the cache -- backend fails
//   - Verify that GetLog(5) does NOT return the entry from the cache
//   - On buggy code: GetLog(5) succeeds (stale cache) -> test FAILS
//   - On fixed code: GetLog(5) returns ErrLogNotFound -> test PASSES
func TestLogCacheStaleDataOnStoreError(t *testing.T) {
	store := NewInmemStore()
	errStore := &injectErrorStore{LogStore: store}
	c, err := NewLogCache(16, errStore)
	if err != nil {
		t.Fatalf("NewLogCache: %v", err)
	}

	// Pre-populate the underlying store with entries 1..4
	for i := 0; i < 4; i++ {
		log := &Log{Index: uint64(i) + 1}
		if err := store.StoreLog(log); err != nil {
			t.Fatalf("StoreLog(%d): %v", i+1, err)
		}
	}

	// Make the next StoreLogs call fail
	errStore.injectFailNext(1)

	// Attempt to store log entry 5 via the LogCache. The backend will fail.
	log5 := &Log{Index: 5}
	err = c.StoreLog(log5)
	if err == nil {
		t.Fatalf("Expected StoreLogs to fail, but it succeeded")
	}
	if !strings.Contains(err.Error(), "injected store error") {
		t.Fatalf("Expected injected store error, got: %v", err)
	}

	// Verify that existing entries (1..4) are still accessible via the cache.
	// They were stored directly in the backend, so they should be found via
	// the cache's fallback to the underlying store.
	var out Log
	for i := 1; i <= 4; i++ {
		if err := c.GetLog(uint64(i), &out); err != nil {
			t.Fatalf("GetLog(%d) should succeed: %v", i, err)
		}
	}

	// THE CRITICAL CHECK: GetLog(5) must NOT succeed.
	// On buggy code, the cache was populated before the backend call, so
	// GetLog(5) returns the cached entry even though it was never persisted.
	// On fixed code, the cache is only populated after a successful backend
	// write, so GetLog(5) falls through to the backend which returns
	// ErrLogNotFound.
	out = Log{}
	err = c.GetLog(5, &out)
	if err == nil {
		t.Fatalf("BUG DETECTED: GetLog(5) returned a cached entry (Index=%d) "+
			"that was NEVER persisted to the backend store. "+
			"The LogCache cached data before verifying the backend write succeeded. "+
			"On restart, this entry would be lost, causing a 'log not found' panic.",
			out.Index)
	}
	if err != ErrLogNotFound {
		t.Fatalf("Expected ErrLogNotFound for index 5, got: %v", err)
	}
	t.Log("CORRECT: GetLog(5) returned ErrLogNotFound -- cache was not polluted by failed store")
}
