package main

import (
	"fmt"
	"io"
	"os"
	"runtime"
	"time"

	"github.com/hashicorp/raft"
)

// MockFSM with a slow Snapshot() to widen the race window.
// The deadlock happens when takeSnapshot() sends on configurationsCh,
// the main loop picks it up but exits (due to shutdown) before responding.
// A slow Snapshot() keeps the snapshot goroutine alive longer, increasing
// the chance that Shutdown() is called while takeSnapshot() is in flight.
type MockFSM struct{}

func (m *MockFSM) Apply(l *raft.Log) interface{} { return nil }
func (m *MockFSM) Snapshot() (raft.FSMSnapshot, error) {
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

func tryOnce() bool {
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
		return false
	}

	r, err := raft.NewRaft(config, &MockFSM{}, store, store, snapStore, transport)
	if err != nil {
		fmt.Fprintf(os.Stderr, "raft error: %v\n", err)
		return false
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
			return false
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
		return false // No deadlock
	case <-time.After(10 * time.Second):
		return true // DEADLOCK detected
	}
}

func main() {
	total := 50
	for i := 1; i <= total; i++ {
		if tryOnce() {
			fmt.Printf("Attempt %d: DEADLOCK\n", i)
			fmt.Println()
			fmt.Printf("FAIL: Bug is present — deadlock on attempt %d/%d\n", i, total)
			os.Exit(1)
		}
		fmt.Printf("Attempt %d: OK\n", i)
	}
	fmt.Println()
	fmt.Printf("PASS: Bug is fixed — all %d runs completed without deadlock\n", total)
	os.Exit(0)
}
