# Setup: etcd #20221

## Project
- **Repository:** https://github.com/etcd-io/etcd
- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/20221

## Clone and checkout buggy version
```bash
git clone https://github.com/etcd-io/etcd.git
cd etcd
git checkout 9fb8c3685fd4573e39470a5451d3f85c0f29bfb1~1
```

## Build
```bash
make build
```

## Dependencies
- Go 1.22+
