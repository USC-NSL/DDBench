# Reproduce: Redpanda #25769

## Prerequisites
- Redpanda running on port 9092 (see setup.md)
- `rpk` or a Kafka client library available

## Step 1: Create a topic

```bash
docker exec redpanda rpk topic create test-compressed -p 1
```

## Step 2: Produce compressed records with known timestamps

Using a Go program with franz-go (or equivalent in any Kafka client library):

```go
package main

import (
    "context"
    "fmt"
    "time"

    "github.com/twmb/franz-go/pkg/kgo"
)

func main() {
    client, err := kgo.NewClient(
        kgo.SeedBrokers("localhost:9092"),
        kgo.ProducerBatchCompression(kgo.GzipCompression()),
        kgo.DefaultProduceTopic("test-compressed"),
        // All records MUST go into a single compressed batch to trigger the bug.
        // Use a large batch size and manual flush to ensure they batch together.
        kgo.ProducerBatchMaxBytes(1<<20),
        kgo.ProducerLinger(5 * time.Second),
    )
    if err != nil {
        panic(err)
    }
    defer client.Close()

    // Produce records with specific timestamps
    timestamps := []time.Time{
        time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC),   // offset 0
        time.Date(2024, 1, 1, 1, 0, 0, 0, time.UTC),   // offset 1
        time.Date(2024, 1, 1, 2, 0, 0, 0, time.UTC),   // offset 2
        time.Date(2024, 1, 1, 3, 0, 0, 0, time.UTC),   // offset 3
        time.Date(2024, 1, 1, 4, 0, 0, 0, time.UTC),   // offset 4
    }

    // Produce all records without flushing so they batch together
    for i, ts := range timestamps {
        record := &kgo.Record{
            Value:     []byte(fmt.Sprintf("record-%d", i)),
            Timestamp: ts,
        }
        client.Produce(context.Background(), record, nil)
    }
    // Flush to send all 5 records in a single compressed batch
    if err := client.Flush(context.Background()); err != nil {
        panic(err)
    }

    fmt.Println("Produced 5 compressed records in a single batch with known timestamps")
}
```

## Step 3: Query ListOffsets for a specific timestamp

```go
// Query for timestamp of record at offset 2
// Expected: offset 2
// Bug: returns wrong offset

import "github.com/twmb/franz-go/pkg/kadm"

adminClient := kadm.NewClient(client)
target := time.Date(2024, 1, 1, 2, 0, 0, 0, time.UTC)
offsets, err := adminClient.ListOffsetsAfterMilli(context.Background(),
    target.UnixMilli(), "test-compressed")
// Check offsets.Lookup("test-compressed", 0).Offset
```

## Alternative: Using kcat

**Note:** The following kcat loop will NOT reproduce the bug because each invocation creates a separate batch. The bug only manifests when multiple records with different timestamps are in the *same* compressed batch. Use the Go program above or a Kafka client that supports batched production with compression.

```bash
# This does NOT work — each kcat call creates a separate batch:
# for i in $(seq 1 5); do
#     echo "record-$i" | kcat -P -b localhost:9092 -t test-compressed -z gzip
# done

# Instead, pipe all records at once so they go into a single batch:
printf "record-0\nrecord-1\nrecord-2\nrecord-3\nrecord-4\n" | kcat -P -b localhost:9092 -t test-compressed -z gzip
# Note: kcat assigns all records the same timestamp in this case,
# so the Go program is the preferred approach for setting distinct timestamps.
```

## Expected result (bug present)

`ListOffsets` returns an incorrect offset for the requested timestamp. For example, querying for the timestamp of record 2 might return offset 0 (beginning of the batch) instead of offset 2.

## Expected result (bug absent)

`ListOffsets` returns the correct offset (2) for the timestamp corresponding to record 2.
