# Setup: etcd #19179

## Project
- **Repository:** https://github.com/etcd-io/etcd
- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/19179

## Clone and checkout buggy version
```bash
git clone https://github.com/etcd-io/etcd.git
cd etcd
git checkout 83cf7bb4fc621f017fcaa9a735194fcec23420b8~1
```

## Build
```bash
make build
```

## Dependencies
- Go 1.23+
