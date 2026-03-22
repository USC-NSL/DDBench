# Verification: ClickHouse #98079

## Test procedure

1. Start ClickHouse Keeper (see setup.md).

2. Verify Keeper is running:
   ```bash
   echo ruok | nc -w 3 localhost 2181
   # Should return: imok
   ```

3. Test using Apache ZooKeeper CLI (requires ZK 3.6+ distribution):
   ```bash
   # Create a test znode first
   echo "create /test-addwatch test" | timeout 5 \
     ./apache-zookeeper-3.8.4-bin/bin/zkCli.sh -server localhost:2181 2>&1

   # Try addWatch
   RESULT=$(echo "addWatch /test-addwatch" | timeout 10 \
     ./apache-zookeeper-3.8.4-bin/bin/zkCli.sh -server localhost:2181 2>&1)
   ```

4. Evaluate:
   ```bash
   if echo "$RESULT" | grep -q "CONNECTIONLOSS\|Connection refused\|KeeperException\|Disconnected"; then
       echo "FAIL: Bug is present — Keeper disconnects client on addWatch"
   elif echo "$RESULT" | grep -q "WatchedEvent.*type:None"; then
       echo "PASS: Bug is fixed — addWatch request handled correctly"
   else
       echo "INCONCLUSIVE: Check output manually: $RESULT"
   fi
   ```

5. Alternative: Java test (more reliable):
   ```bash
   # Build and run the Java test client from reproduce.md
   cd test-addwatch-project
   mvn -q compile exec:java -Dexec.mainClass="TestAddWatch" 2>&1 | tail -5
   # PASS: Output includes "the client stayed connected"
   # FAIL: Output shows reconnection attempts
   ```

6. Cleanup:
   ```bash
   echo "delete /test-addwatch" | timeout 5 \
     ./apache-zookeeper-3.8.4-bin/bin/zkCli.sh -server localhost:2181 2>/dev/null
   ```

## Verdict criteria
- **FAIL (bug present):** Keeper disconnects the client upon receiving an `addWatch` request; connection is lost.
- **PASS (bug fixed):** Keeper properly handles the `addWatch` request; client stays connected and receives watch events.
