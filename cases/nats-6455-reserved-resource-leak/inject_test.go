package server

import (
	"errors"
	"testing"
	"time"

	"github.com/nats-io/nats.go"
)

// TestJetStreamClusterReservedResourcesAccountingAfterClusterReset verifies
// that reserved resources (MaxBytes) are not double-counted after a clustered
// stream undergoes resetClusteredState().
//
// Bug (nats-io/nats-server#6455): When a stream encounters a "last sequence
// mismatch" error, resetClusteredState() stops the stream and recreates it
// via processClusterCreateStream(). The recreation unconditionally calls
// reserveStreamResources(), adding MaxBytes to the server's reserved tally
// again without releasing the previous reservation. After repeated resets
// the server reports disk full even though actual usage is unchanged.
func TestDDBenchOracleReservedResourcesAfterClusterReset(t *testing.T) {
	for _, clusterResetErr := range []error{errLastSeqMismatch, errFirstSequenceMismatch} {
		t.Run(clusterResetErr.Error(), func(t *testing.T) {
			c := createJetStreamClusterExplicit(t, "R3S", 3)
			defer c.shutdown()

			nc, js := jsClientConnect(t, c.randomServer())
			defer nc.Close()

			maxBytes := int64(1024 * 1024 * 1024)
			_, err := js.AddStream(&nats.StreamConfig{
				Name:     "TEST",
				Subjects: []string{"foo"},
				Replicas: 3,
				MaxBytes: maxBytes,
			})
			require_NoError(t, err)

			sl := c.streamLeader(globalAccountName, "TEST")

			mem, store, err := sl.JetStreamReservedResources()
			require_NoError(t, err)
			require_Equal(t, mem, 0)
			require_Equal(t, store, maxBytes)

			acc, err := sl.lookupAccount(globalAccountName)
			require_NoError(t, err)
			mset, err := acc.lookupStream("TEST")
			require_NoError(t, err)

			sjs := sl.getJetStream()
			rn := mset.raftNode()
			sa := mset.streamAssignment()
			sjs.mu.RLock()
			saGroupNode := sa.Group.node
			sjs.mu.RUnlock()
			require_NotNil(t, sa)
			require_Equal(t, rn, saGroupNode)

			require_True(t, mset.resetClusteredState(clusterResetErr))

			checkFor(t, 5*time.Second, 500*time.Millisecond, func() error {
				sjs.mu.RLock()
				defer sjs.mu.RUnlock()
				if sa.Group.node == nil || sa.Group.node == saGroupNode {
					return errors.New("waiting for reset to complete")
				}
				return nil
			})

			mem, store, err = sl.JetStreamReservedResources()
			require_NoError(t, err)
			require_Equal(t, mem, 0)
			require_Equal(t, store, maxBytes)
		})
	}
}
