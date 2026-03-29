# Setup: etcd #17529

## Project
- **Repository:** https://github.com/etcd-io/etcd
- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/17529

## Clone and checkout buggy version
```bash
git clone https://github.com/etcd-io/etcd.git
cd etcd
git checkout fca3e8a9b5c5b52a65d4ac0fe2fd7fdc7577551a~1
```

## Build
```bash
make build
```

## Dependencies
- Go 1.22+
