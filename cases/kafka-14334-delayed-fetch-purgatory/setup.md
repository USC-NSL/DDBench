# Setup: Kafka #14334

## Project
- **Repository:** https://github.com/apache/kafka
- **Language:** Scala/Java
- **Issue:** https://issues.apache.org/jira/browse/KAFKA-14334

## Clone and checkout buggy version
```bash
git clone https://github.com/apache/kafka.git
cd kafka
git checkout dbf5826cd545820652ed6d136727aa80a03f4f54~1
```

## Build
```bash
./gradlew jar -x test -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet
```
