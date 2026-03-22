# Setup: NATS #6888

## Project
- **Repository:** https://github.com/nats-io/nats-server
- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/6888

## Clone and checkout buggy version
```bash
git clone https://github.com/nats-io/nats-server.git
cd nats-server
git checkout v2.10.20
```

## Build
```bash
go build -o nats-server .
```

## Deploy: 3-node JetStream cluster

`server1.conf`:
```
server_name: n1
listen: 0.0.0.0:4222
http: 0.0.0.0:8222
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
```

`server2.conf`:
```
server_name: n2
listen: 0.0.0.0:4223
http: 0.0.0.0:8223
jetstream {
    store_dir: /tmp/nats-js-2
}
cluster {
    name: test-cluster
    listen: 0.0.0.0:6223
    routes: [
        nats://localhost:6222,
        nats://localhost:6223,
        nats://localhost:6224,
    ]
}
```

`server3.conf`:
```
server_name: n3
listen: 0.0.0.0:4224
http: 0.0.0.0:8224
jetstream {
    store_dir: /tmp/nats-js-3
}
cluster {
    name: test-cluster
    listen: 0.0.0.0:6224
    routes: [
        nats://localhost:6222,
        nats://localhost:6223,
        nats://localhost:6224,
    ]
}
```

Start the cluster:
```bash
./nats-server -c server1.conf &
./nats-server -c server2.conf &
./nats-server -c server3.conf &
sleep 3
```
