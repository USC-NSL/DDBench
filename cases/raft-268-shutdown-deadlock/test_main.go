package main

import (
	"fmt"
	"io"
	"os"
	"runtime"
	"sync/atomic"
	"time"

	"github.com/hashicorp/raft"
)

// MockFSM with a slow Snapshot() to widen the race window.
// The deadlock happens when takeSnapshot() sends on configurationsCh,
// the main loop picks it up but exits (due to shutdown) before responding.
// A slow Snapshot() keeps the snapshot goroutine alive longer, increasing
// the chance that Shutdown() is called while takeSnapshot() is in flight.
type MockFSM struct{}

// snapshots counts FSM.Snapshot() calls across all attempts. If it stays 0, the
// trigger (a snapshot in flight during Shutdown) never happened and the run
// proves nothing.
var snapshots int64

func (m *MockFSM) Apply(l *raft.Log) interface{} { return nil }
func (m *MockFSM) Snapshot() (raft.FSMSnapshot, error) {
	atomic.AddInt64(&snapshots, 1)
	// Sleep long enough that shutdown is likely to be called while
	// takeSnapshot is between the FSM snapshot and the configurationsCh send.
	time.Sleep(200 * time.Millisecond)
	return &MockSnapshot{}, nil
}
func (m *MockFSM) Restore(r io.ReadCloser) error { return nil }

type MockSnapshot struct{}

func (m *MockSnapshot) Persist(sink raft.SnapshotSink) error {
	sink.Write([]byte("snapshot"))
	return sink.Close()
}
func (m *MockSnapshot) Release() {}

type outcome int

const (
	clean    outcome = iota // Shutdown returned
	deadlock                // Shutdown did not return within 10s
	noLeader                // the node never became leader (code under test broken)
	infra                   // harness could not set up the node
)

func tryOnce() outcome {
	// Limit parallelism to increase goroutine interleaving on the
	// scheduler, making the race window more likely to hit.
	runtime.GOMAXPROCS(1)

	config := raft.DefaultConfig()
	config.LocalID = "node1"
	// Very aggressive snapshot settings: threshold=1 means every single
	// log entry can trigger a snapshot, interval=10ms means the snapshot
	// goroutine checks frequently.
	config.SnapshotThreshold = 1
	config.SnapshotInterval = 10 * time.Millisecond
	// Faster election so we don't waste time waiting for leader.
	config.HeartbeatTimeout = 100 * time.Millisecond
	config.ElectionTimeout = 100 * time.Millisecond
	config.LeaderLeaseTimeout = 50 * time.Millisecond
	// Suppress logs to avoid I/O overhead.
	config.LogOutput = io.Discard

	store := raft.NewInmemStore()
	snapStore := raft.NewInmemSnapshotStore()
	transport, err := raft.NewTCPTransport("127.0.0.1:0", nil, 3, 5*time.Second, io.Discard)
	if err != nil {
		fmt.Fprintf(os.Stderr, "transport error: %v\n", err)
		return infra
	}

	r, err := raft.NewRaft(config, &MockFSM{}, store, store, snapStore, transport)
	if err != nil {
		fmt.Fprintf(os.Stderr, "raft error: %v\n", err)
		return noLeader
	}

	// Bootstrap as single-node cluster.
	configuration := raft.Configuration{
		Servers: []raft.Server{
			{ID: "node1", Address: transport.LocalAddr()},
		},
	}
	r.BootstrapCluster(configuration)

	// Wait for leader election (with fast timeouts this should be <500ms).
	deadline := time.After(5 * time.Second)
	for r.State() != raft.Leader {
		select {
		case <-deadline:
			r.Shutdown()
			return noLeader
		case <-time.After(10 * time.Millisecond):
		}
	}

	// Apply entries to cross the snapshot threshold. Each entry may trigger
	// a snapshot attempt due to SnapshotThreshold=1.
	for i := 0; i < 5; i++ {
		r.Apply([]byte(fmt.Sprintf("e%d", i)), 2*time.Second)
	}

	// Give the snapshot goroutine a moment to start takeSnapshot().
	// The 200ms FSM.Snapshot() sleep means the goroutine will be busy
	// for ~200ms after a snapshot triggers. We want to call Shutdown()
	// while it's between the FSM snapshot call and the configurationsCh
	// send (or right after the send).
	time.Sleep(50 * time.Millisecond)

	// Call Shutdown and detect deadlock via timeout.
	done := make(chan struct{})
	go func() {
		f := r.Shutdown()
		f.Error()
		close(done)
	}()

	select {
	case <-done:
		return clean
	case <-time.After(10 * time.Second):
		return deadlock
	}
}

func main() {
	// Exit codes follow the DDBench contract: 0 PASS, 1 FAIL, 2 ERROR.
	total := 50
	for i := 1; i <= total; i++ {
		switch tryOnce() {
		case deadlock:
			fmt.Printf("Attempt %d: DEADLOCK\n", i)
			fmt.Println()
			fmt.Printf("FAIL: Bug is present — Shutdown() deadlocked on attempt %d/%d\n", i, total)
			os.Exit(1)
		case noLeader:
			fmt.Println()
			fmt.Printf("FAIL: the single-node cluster did not start or elect a leader (attempt %d)\n", i)
			os.Exit(1)
		case infra:
			fmt.Println()
			fmt.Printf("ERROR: harness could not set up the node (attempt %d)\n", i)
			os.Exit(2)
		}
		fmt.Printf("Attempt %d: OK\n", i)
	}
	if atomic.LoadInt64(&snapshots) == 0 {
		fmt.Println()
		fmt.Println("ERROR: no FSM snapshot was ever taken, so the shutdown race was never exercised")
		os.Exit(2)
	}
	fmt.Println()
	fmt.Printf("PASS: Bug is fixed — all %d attempts shut down cleanly (%d snapshots taken)\n", total, atomic.LoadInt64(&snapshots))
	os.Exit(0)
}
