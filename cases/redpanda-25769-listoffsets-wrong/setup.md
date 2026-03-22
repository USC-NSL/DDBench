# Setup: Redpanda — ListOffsets Returns Incorrect Results for Compressed Batches

## Project
- **Repository:** https://github.com/redpanda-data/redpanda
- **Language:** C++
- **Issue:** https://github.com/redpanda-data/redpanda/issues/25769
- **Fix PR:** https://github.com/redpanda-data/redpanda/pull/25932

## Option A: Docker (recommended)

Use a version before the fix:
```bash
docker pull redpandadata/redpanda:v24.3.7
```

Start a single-node Redpanda cluster:
```bash
docker run -d --name redpanda --network host \
  redpandadata/redpanda:v24.3.7 \
  redpanda start \
  --smp 1 \
  --memory 1G \
  --overprovisioned \
  --kafka-addr 0.0.0.0:9092 \
  --advertise-kafka-addr localhost:9092 \
  --pandaproxy-addr 0.0.0.0:8082 \
  --advertise-pandaproxy-addr localhost:8082
```

Verify:
```bash
docker exec redpanda rpk cluster info
```

## Option B: Build from source

```bash
git clone https://github.com/redpanda-data/redpanda.git
cd redpanda
# Checkout parent of fix commit
git checkout 18b0c24d7b306add4a1390fc2c56a5de5420f567~1
git submodule update --init --recursive

# Build (requires clang 16+, cmake, ninja)
mkdir build && cd build
cmake .. -GNinja -DCMAKE_BUILD_TYPE=Release
ninja redpanda
```

## Client setup

Install the franz-go CLI tools or a Kafka client that supports compression:
```bash
# Option 1: rpk (bundled with Redpanda)
docker exec redpanda rpk topic create test-topic

# Option 2: kcat (formerly kafkacat)
brew install kcat  # macOS
# or: apt-get install kafkacat  # Linux

# Option 3: franz-go (Go library for programmatic testing)
go install github.com/twmb/franz-go/cmd/...@latest
```
