# Race Detector Output

Obtained by running `go test -race -v -run TestWQConsumerPartitionRace -count=1 -timeout 120s ./server/` against the buggy build.

## Output

```
fatal error: concurrent map iteration and map write

goroutine 38 [running]:
internal/runtime/maps.fatal({0x204d978?, 0x3?})
	/root/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.24.11.linux-amd64/src/runtime/panic.go:1058 +0x18
internal/runtime/maps.(*Iter).Next(0xc00034bc20?)
	/root/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.24.11.linux-amd64/src/internal/runtime/maps/table.go:683 +0x86
github.com/nats-io/nats-server/v2/server.(*stream).partitionUnique(0xc000166488, {0xc00160436c, 0x4}, {0xc003488010, 0x1, 0x4ae400?})
	/workspace/worktrees/nats-7707-wq-consumer-map-crash/server/stream.go:7478 +0x149
github.com/nats-io/nats-server/v2/server.(*stream).addConsumerWithAssignment(0xc000166488, 0xc001aab050, {0x0, 0x0}, 0x0, 0x0, 0x0, 0x0)
	/workspace/worktrees/nats-7707-wq-consumer-map-crash/server/consumer.go:1044 +0x20fa
```
