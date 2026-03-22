# Setup: Dragonfly #6822

## Project
- **Repository:** https://github.com/dragonflydb/dragonfly
- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6822

## Clone and checkout buggy version
```bash
git clone --recurse-submodules https://github.com/dragonflydb/dragonfly.git
cd dragonfly
git checkout 4df1a91450cd504c37bff5730944a3569996abff~1
git submodule update --init --recursive
```

## Build
```bash
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Release
```

## Alternative: Docker
```bash
# Find the Docker image tag just before the fix commit
docker pull dragonflydb/dragonfly:v1.27.1
```
