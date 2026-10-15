package routine

import (
	"context"
	"sync/atomic"
	"testing"

	"github.com/hashicorp/consul/sdk/testutil"
	"github.com/hashicorp/consul/sdk/testutil/retry"
	"github.com/stretchr/testify/require"
)

// TestManager_IsRunningAfterParentContextCancel verifies that IsRunning()
// returns false after the parent context is cancelled, even while the
// goroutine is still blocking on a long-running call (e.g., a cross-DC RPC).
//
// Simulates the ACL replication scenario where the same Consul server loses
// and immediately regains leadership. revokeLeadership() may not have called
// stopACLReplication() yet when establishLeadership() calls startACLReplication(),
// which checks IsRunning() before attempting to restart the routines. If
// IsRunning() returns true for a cancelled-but-blocking routine, the ACL
// replication routines are never restarted and the secondary DC accumulates
// permanently stale ACL state.
func TestDDBenchOracleIsRunningAfterParentCancel(t *testing.T) {
	t.Parallel()

	var running uint32
	unblock := make(chan struct{})
	defer close(unblock) // ensure goroutine exits on test completion

	// leaderCtx simulates the context passed to establishLeadership() /
	// startACLReplication(). It is cancelled when Raft steps down (stopCh
	// closes). The ACL replication routine's own context is derived from this.
	leaderCtx, leaderCancel := context.WithCancel(context.Background())
	defer leaderCancel()

	mgr := NewManager(testutil.Logger(t))

	// Simulate a long-running ACL replication goroutine that blocks on a
	// cross-DC RPC even after its context is cancelled.
	require.NoError(t, mgr.Start(leaderCtx, "acl-policy-replication", func(ctx context.Context) error {
		atomic.StoreUint32(&running, 1)
		defer atomic.StoreUint32(&running, 0)
		<-ctx.Done() // wait for context cancellation (leadership lost)
		<-unblock    // simulate: blocking RPC hasn't returned yet
		return nil
	}))

	// Confirm the goroutine started
	retry.Run(t, func(r *retry.R) {
		require.Equal(r, uint32(1), atomic.LoadUint32(&running))
		require.True(r, mgr.IsRunning("acl-policy-replication"))
	})

	// Leadership is lost: parent context cancelled (stopCh closed in leaderLoop).
	// revokeLeadership() will eventually call Stop(), but the new leaderLoop
	// may call startACLReplication() / IsRunning() before that happens.
	leaderCancel()

	// IsRunning() MUST return false here: the parent context is done, so there
	// is no point in treating this routine as "still running" — its leadership
	// term is over regardless of whether the goroutine has exited yet.
	//
	// On buggy commit: running() checks only stoppedCh (still open while goroutine
	//   is blocking) → IsRunning = true → startACLReplication returns early →
	//   ACL replication never restarted → secondary DC permanently stale. FAIL.
	//
	// On fixed commit: running() also checks cancelCh (= leaderCtx.Done(), now
	//   closed) → IsRunning = false → startACLReplication proceeds to Start() →
	//   ACL replication restarts correctly. PASS.
	require.False(t, mgr.IsRunning("acl-policy-replication"),
		"IsRunning returned true after parent context was cancelled while goroutine "+
			"is still blocking on a long-running call. This causes startACLReplication() "+
			"to skip restarting the routine after leadership re-election, leaving the "+
			"secondary datacenter with permanently stale ACL state.")

	// Verify that a new routine can also be started (simulates re-establishment).
	newLeaderCtx, newLeaderCancel := context.WithCancel(context.Background())
	defer newLeaderCancel()

	var newRunning uint32
	require.NoError(t, mgr.Start(newLeaderCtx, "acl-policy-replication", func(ctx context.Context) error {
		atomic.StoreUint32(&newRunning, 1)
		defer atomic.StoreUint32(&newRunning, 0)
		<-ctx.Done()
		return nil
	}))

	retry.Run(t, func(r *retry.R) {
		require.Equal(r, uint32(1), atomic.LoadUint32(&newRunning),
			"new ACL replication routine failed to start after leadership re-election")
		require.True(r, mgr.IsRunning("acl-policy-replication"))
	})
}
