# Setup: Nomad — Scheduler Panic on System Job Deployment Handling

## Project
- **Repository:** https://github.com/hashicorp/nomad
- **Language:** Go
- **Issue:** https://github.com/hashicorp/nomad/issues/27567
- **Fix PR:** https://github.com/hashicorp/nomad/pull/27571

## Option A: Pre-built binary (recommended)

Download the buggy version (v1.11.2):
```bash
# Linux amd64
wget https://releases.hashicorp.com/nomad/1.11.2/nomad_1.11.2_linux_amd64.zip
unzip nomad_1.11.2_linux_amd64.zip
chmod +x nomad

# macOS arm64
wget https://releases.hashicorp.com/nomad/1.11.2/nomad_1.11.2_darwin_arm64.zip
unzip nomad_1.11.2_darwin_arm64.zip
chmod +x nomad
```

Start Nomad in dev mode:
```bash
./nomad agent -dev
```

Verify:
```bash
./nomad node status
```

## Option B: Build from source

```bash
git clone https://github.com/hashicorp/nomad.git
cd nomad
git checkout v1.11.2
make bootstrap
make dev
```

The binary will be at `./bin/nomad`.

Start in dev mode:
```bash
./bin/nomad agent -dev
```

## Option C: Docker

```bash
docker pull hashicorp/nomad:1.11.2
docker run -d --name nomad --network host \
  --privileged \
  hashicorp/nomad:1.11.2 agent -dev -bind=0.0.0.0
```

## Prerequisites
- `nomad` CLI (same version or compatible)
- `curl` or `jq` for API inspection
