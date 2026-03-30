# Setup: Kafka #15784

## Project
- **Repository:** https://github.com/apache/kafka
- **Language:** Scala/Java
- **Issue:** https://issues.apache.org/jira/browse/KAFKA-15784

## Clone and checkout buggy version
```bash
git clone https://github.com/apache/kafka.git
cd kafka
git checkout e4249b69bda215d308ac5580a89fcc58ca054b97~1
```

## Build
```bash
./gradlew jar -x test -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet
```
