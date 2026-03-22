# Setup: Seastar #2202

## Project
- **Repository:** https://github.com/scylladb/seastar
- **Language:** C++
- **Issue:** https://github.com/scylladb/seastar/issues/2202

## Clone and checkout buggy version

```bash
git clone https://github.com/scylladb/seastar.git
cd seastar
git checkout v23.1.0
git submodule update --init --recursive
```

## Install dependencies

On Ubuntu/Debian:
```bash
sudo ./install-dependencies.sh
```

On Fedora:
```bash
sudo ./install-dependencies.sh
```

## Build

```bash
./configure.py --mode=dev --cook fmt
ninja -C build/dev
```

## Build and run tests

```bash
ninja -C build/dev tests/unit/alloc_test
```
