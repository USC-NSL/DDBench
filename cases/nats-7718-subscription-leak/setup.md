# Setup: NATS #7718

## Project
- **Repository:** https://github.com/nats-io/nats-server
- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/7718

## Clone and checkout buggy version
```bash
git clone https://github.com/nats-io/nats-server.git
cd nats-server
git checkout b72becc443073300e5599d06fa0cde1cd5518589~1
```

## Build
```bash
go build -o nats-server .
```

## Deploy: 3-node cluster with JetStream and overlapping stream imports

Create server configs:

`server1.conf`:
```
server_name: n1
listen: 0.0.0.0:4222
jetstream {
    store_dir: /tmp/nats-js-1
}
cluster {
    name: test-cluster
    listen: 0.0.0.0:6222
    routes: [
        nats://localhost:6222,
        nats://localhost:6223,
        nats://localhost:6224,
    ]
}
accounts {
    SYS { users: [{user: sys, password: sys}] }
    A {
        jetstream: enabled
        users: [{user: a, password: a}]
        exports: [
            {stream: "events.>"}
        ]
    }
    B {
        jetstream: enabled
        users: [{user: b, password: b}]
        imports: [
            {stream: {account: A, subject: "events.>"}}
            {stream: {account: A, subject: "events.critical.>"}}
        ]
    }
}
system_account: SYS
```

Create similar `server2.conf` and `server3.conf` with different ports (4223/6223, 4224/6224) and store dirs.

```bash
./nats-server -c server1.conf &
./nats-server -c server2.conf &
./nats-server -c server3.conf &
```
