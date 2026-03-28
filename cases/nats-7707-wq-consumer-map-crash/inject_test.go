package server

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/nats-io/nats.go"
)

// TestWQConsumerPartitionRace triggers a concurrent map iteration and map
// write on the consumer partition map of a WorkQueue stream.
//
// The bug (nats-io/nats-server#7707): in addConsumerWithAssignment, the
// stream lock is released BEFORE calling partitionUnique(). This function
// iterates mset.consumers (a Go map) without the lock. Concurrent consumer
// create/delete operations modify the map, causing the Go runtime to crash
// with "fatal error: concurrent map iteration and map write".
//
// Key design choices for reliable reproduction:
// 1. SEPARATE connections per goroutine — a single NATS connection
//    serializes requests, preventing true concurrency on the server.
// 2. Many workers (32) to maximize overlap probability.
// 3. Pre-seed 256 consumers so the map is large (longer iteration =
//    wider race window). 32 was insufficient for reliable detection.
// 4. Duration of 15s to give the race enough attempts to fire.
func TestWQConsumerPartitionRace(t *testing.T) {
	conf := createConfFile(t, []byte(fmt.Sprintf(`
		listen: 127.0.0.1:-1
		jetstream: { store_dir: %q }
	`, t.TempDir())))
	s, _ := RunServerWithConfig(conf)
	if s == nil {
		t.Fatal("Failed to start server")
	}
	defer s.Shutdown()

	nc0, js0 := jsClientConnect(t, s)
	defer nc0.Close()

	// Create a WorkQueue retention stream.
	_, err := js0.AddStream(&nats.StreamConfig{
		Name:      "WQ_RACE",
		Subjects:  []string{"wq.>"},
		Retention: nats.WorkQueuePolicy,
		Storage:   nats.MemoryStorage,
	})
	if err != nil {
		t.Fatalf("Failed to create stream: %v", err)
	}

	// Pre-seed 256 consumers to enlarge the map. A bigger map means
	// partitionUnique iterates longer, widening the race window.
	// 32 consumers was insufficient — the iteration completed too fast
	// for the race window to be hit. 256 makes it reliably reproducible.
	for i := 0; i < 256; i++ {
		_, _ = js0.AddConsumer("WQ_RACE", &nats.ConsumerConfig{
			Durable:       fmt.Sprintf("SEED_%d", i),
			FilterSubject: fmt.Sprintf("wq.seed.%d", i),
			AckPolicy:     nats.AckExplicitPolicy,
		})
	}

	const numWorkers = 32
	const duration = 15 * time.Second

	var wg sync.WaitGroup
	stop := make(chan struct{})

	// Publisher goroutines — each with its own connection.
	for p := 0; p < 4; p++ {
		wg.Add(1)
		go func(pid int) {
			defer wg.Done()
			pnc, err := nats.Connect(s.ClientURL())
			if err != nil {
				return
			}
			defer pnc.Close()
			pjs, err := pnc.JetStream()
			if err != nil {
				return
			}
			i := 0
			for {
				select {
				case <-stop:
					return
				default:
					subj := fmt.Sprintf("wq.partition.%d", i%numWorkers)
					pjs.Publish(subj, []byte("payload"))
					i++
				}
			}
		}(p)
	}

	// Consumer churner goroutines — each with its OWN connection so the
	// server handles API requests on separate goroutines, maximizing the
	// chance of overlapping partitionUnique iteration with map mutations.
	for w := 0; w < numWorkers; w++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			wnc, err := nats.Connect(s.ClientURL())
			if err != nil {
				return
			}
			defer wnc.Close()
			wjs, err := wnc.JetStream()
			if err != nil {
				return
			}

			subj := fmt.Sprintf("wq.partition.%d", id)
			name := fmt.Sprintf("C_%d", id)
			for {
				select {
				case <-stop:
					return
				default:
					_, _ = wjs.AddConsumer("WQ_RACE", &nats.ConsumerConfig{
						Durable:       name,
						FilterSubject: subj,
						AckPolicy:     nats.AckExplicitPolicy,
					})
					_, _ = wjs.UpdateConsumer("WQ_RACE", &nats.ConsumerConfig{
						Durable:       name,
						FilterSubject: subj,
						AckPolicy:     nats.AckExplicitPolicy,
						MaxDeliver:    2,
					})
					_ = wjs.DeleteConsumer("WQ_RACE", name)
				}
			}
		}(w)
	}

	time.Sleep(duration)
	close(stop)
	wg.Wait()
}
