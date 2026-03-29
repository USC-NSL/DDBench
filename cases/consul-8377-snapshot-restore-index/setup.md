# Setup: Consul #8377

## Project
- **Repository:** https://github.com/hashicorp/consul
- **Language:** Go
- **Issue:** https://github.com/hashicorp/consul/issues/8377

## Clone and checkout buggy version
```bash
git clone https://github.com/hashicorp/consul.git
cd consul
git checkout 9bc9d3014d2d8f48c4c87926bfb98c8536364532~1
```

## Build
```bash
make dev-build
```

The binary is produced at `bin/consul`.

## Deploy
Start a 3-node cluster on localhost using different ports for each server:

```bash
# Server 1 (bootstrap)
./bin/consul agent -server -bootstrap-expect=3 -data-dir=/tmp/consul1 \
  -bind=127.0.0.1 -client=127.0.0.1 \
  -http-port=18377 -server-port=18301 -serf-lan-port=18311 -dns-port=18601 \
  -node=server1 -datacenter=dc1

# Server 2 (joins server 1)
./bin/consul agent -server -data-dir=/tmp/consul2 \
  -bind=127.0.0.1 -client=127.0.0.1 \
  -http-port=18378 -server-port=18302 -serf-lan-port=18312 -dns-port=18602 \
  -node=server2 -datacenter=dc1 -retry-join=127.0.0.1:18311

# Server 3 (joins server 1)
./bin/consul agent -server -data-dir=/tmp/consul3 \
  -bind=127.0.0.1 -client=127.0.0.1 \
  -http-port=18379 -server-port=18303 -serf-lan-port=18313 -dns-port=18603 \
  -node=server3 -datacenter=dc1 -retry-join=127.0.0.1:18311
```
