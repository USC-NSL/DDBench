# Setup: etcd #20893

## Project
- **Repository:** https://github.com/etcd-io/etcd
- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/20893

## Clone and checkout buggy version
```bash
git clone https://github.com/etcd-io/etcd.git
cd etcd
git checkout c58e6f1caf7dfe07da002230a2b61d664ab21a34~1
```

## Build
```bash
make build
```

The binaries will be in `bin/`:
- `bin/etcd`
- `bin/etcdctl`
- `bin/etcdutl`

## Dependencies
- Go 1.22+
