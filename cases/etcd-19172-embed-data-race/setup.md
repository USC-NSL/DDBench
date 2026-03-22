# Setup: etcd #19172

## Project
- **Repository:** https://github.com/etcd-io/etcd
- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/19172

## Clone and checkout buggy version
```bash
git clone https://github.com/etcd-io/etcd.git
cd etcd
git checkout 43431bd6f83b60d13a29ef9df53d7f04fe63fcfd~1
```

## Build
```bash
make build
```

## Dependencies
- Go 1.22+
