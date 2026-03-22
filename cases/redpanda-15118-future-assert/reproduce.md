# Reproduce: Redpanda #15118

## Step 1: Start Redpanda with authentication enabled
```bash
# Create config with SASL authentication
cat > /tmp/redpanda.yaml <<EOF
redpanda:
  data_directory: /tmp/redpanda-data
  node_id: 0
  rpc_server:
    address: "0.0.0.0"
    port: 33145
  kafka_api:
    address: "0.0.0.0"
    port: 9092
    authentication_method: sasl
  admin:
    address: "0.0.0.0"
    port: 9644
  developer_mode: true
EOF

rm -rf /tmp/redpanda-data
./build/release/bin/redpanda \
  --redpanda-cfg /tmp/redpanda.yaml \
  --smp 2 \
  --memory 2G &
RPANDA_PID=$!
sleep 5

# Create a valid SASL user via admin API
curl -X POST http://localhost:9644/v1/security/users \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123","algorithm":"SCRAM-SHA-256"}'
```

## Step 2: Generate sustained Kafka client load with auth failures
```bash
# Use kafka-producer-perf-test or a custom script that connects with WRONG credentials
# This triggers do_authenticate failures repeatedly

# Option A: Using kafka tools (requires Kafka client tools installed)
# Produce with bad credentials
for i in $(seq 1 100); do
  timeout 2 kafka-console-producer \
    --broker-list localhost:9092 \
    --topic test \
    --producer-property security.protocol=SASL_PLAINTEXT \
    --producer-property sasl.mechanism=SCRAM-SHA-256 \
    --producer-property sasl.jaas.config='org.apache.kafka.common.security.scram.ScramLoginModule required username="baduser" password="badpass";' \
    <<< "message-$i" 2>/dev/null &
done

# Option B: Using kcat (formerly kafkacat)
for i in $(seq 1 100); do
  echo "msg-$i" | timeout 2 kcat -b localhost:9092 \
    -X security.protocol=SASL_PLAINTEXT \
    -X sasl.mechanism=SCRAM-SHA-256 \
    -X sasl.username=baduser \
    -X sasl.password=badpass \
    -P -t test 2>/dev/null &
done

# Also generate valid load simultaneously
for i in $(seq 1 50); do
  echo "valid-msg-$i" | timeout 2 kcat -b localhost:9092 \
    -X security.protocol=SASL_PLAINTEXT \
    -X sasl.mechanism=SCRAM-SHA-256 \
    -X sasl.username=admin \
    -X sasl.password=admin123 \
    -P -t test 2>/dev/null &
done

wait
```

## Step 3: Repeat and watch for crash
```bash
# Repeat step 2 multiple times — the crash is timing-dependent
for attempt in $(seq 1 10); do
  echo "Attempt $attempt"
  # Run the auth failure load from step 2
  sleep 2

  if ! kill -0 $RPANDA_PID 2>/dev/null; then
    echo "Redpanda crashed on attempt $attempt"
    break
  fi
done
```

## Expected result (bug present)
Redpanda crashes with a Seastar future assertion or broken_promise error after sustained authentication failures under load.
