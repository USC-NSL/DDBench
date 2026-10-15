package raft

import (
	"fmt"
	"sync"
	"testing"
	"time"

	hclog "github.com/hashicorp/go-hclog"
)

// TestCandidateAppendEntriesRaceWithTCP triggers the data race between
// runCandidate's defer (writing candidateFromLeadershipTransfer=false on
// the main goroutine) and processHeartbeat→appendEntries (reading it on
// the TCP handler goroutine).
//
// Race-maximization strategy:
//   - NetworkTransport (TCP): required — InmemTransport processes all RPCs
//     on the main goroutine via rpcCh, so the race is impossible there.
//   - Run 5 INDEPENDENT 3-node clusters in parallel, each doing rapid
//     leadership transfers. Each cluster is an independent race source.
//     The Go race detector tracks all goroutines globally, so races from
//     any cluster are detected.
//   - Each cluster does 200 transfers with continuous write load.
//   - Total: 5 clusters × 200 transfers = 1000 race windows per test run.
func TestDDBenchOracleCandidateAppendEntriesRace(t *testing.T) {
	const numClusters = 5
	const numNodes = 3
	const transfers = 200

	var wg sync.WaitGroup
	for c := 0; c < numClusters; c++ {
		wg.Add(1)
		go func(clusterID int) {
			defer wg.Done()
			ddbenchRunClusterWithTransfers(t, clusterID, numNodes, transfers)
		}(c)
	}
	wg.Wait()
}

func ddbenchRunClusterWithTransfers(t *testing.T, clusterID, numNodes, transfers int) {
	conf := inmemConfig(t)
	conf.Logger = hclog.New(&hclog.LoggerOptions{Level: hclog.Error})
	conf.HeartbeatTimeout = 50 * time.Millisecond
	conf.ElectionTimeout = 50 * time.Millisecond
	conf.LeaderLeaseTimeout = 25 * time.Millisecond
	conf.CommitTimeout = 5 * time.Millisecond

	nodes := make([]*Raft, numNodes)
	transports := make([]*NetworkTransport, numNodes)

	for i := 0; i < numNodes; i++ {
		c := *conf
		c.LocalID = ServerID(fmt.Sprintf("c%d-n%d", clusterID, i))
		store := NewInmemStore()
		snap := NewInmemSnapshotStore()
		var err error
		transports[i], err = NewTCPTransport("127.0.0.1:0", nil, 3, 5*time.Second, nil)
		if err != nil {
			t.Errorf("cluster %d: transport: %v", clusterID, err)
			return
		}
		nodes[i], err = NewRaft(&c, &MockFSM{}, store, store, snap, transports[i])
		if err != nil {
			t.Errorf("cluster %d: raft: %v", clusterID, err)
			return
		}
	}

	defer func() {
		for _, n := range nodes {
			n.Shutdown()
		}
		for _, tr := range transports {
			tr.Close()
		}
	}()

	servers := make([]Server, numNodes)
	for i := 0; i < numNodes; i++ {
		servers[i] = Server{
			ID:      ServerID(fmt.Sprintf("c%d-n%d", clusterID, i)),
			Address: transports[i].LocalAddr(),
		}
	}
	nodes[0].BootstrapCluster(Configuration{Servers: servers})

	// Wait for leader
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		for _, n := range nodes {
			if n.State() == Leader {
				goto found
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	return // no leader — skip silently
found:

	// Warm up
	for _, n := range nodes {
		if n.State() == Leader {
			for i := 0; i < 10; i++ {
				n.Apply([]byte("init"), 5*time.Second)
			}
			break
		}
	}
	time.Sleep(100 * time.Millisecond)

	// Continuous writes to keep heartbeat pipeline hot
	stop := make(chan struct{})
	var wwg sync.WaitGroup
	for w := 0; w < 2; w++ {
		wwg.Add(1)
		go func() {
			defer wwg.Done()
			for {
				select {
				case <-stop:
					return
				default:
				}
				for _, n := range nodes {
					if n.State() == Leader {
						n.Apply([]byte("x"), 500*time.Millisecond)
						break
					}
				}
			}
		}()
	}

	// Rapid leadership transfers
	for round := 0; round < transfers; round++ {
		for _, n := range nodes {
			if n.State() == Leader {
				n.LeadershipTransfer()
				break
			}
		}
		time.Sleep(30 * time.Millisecond)
	}

	close(stop)
	wwg.Wait()
}
