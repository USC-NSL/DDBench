# Setup: Kafka #15170

## Project
- **Repository:** https://github.com/apache/kafka
- **Language:** Java
- **Issue:** https://issues.apache.org/jira/browse/KAFKA-15170

## Clone and checkout buggy version
```bash
git clone https://github.com/apache/kafka.git
cd kafka
git checkout f0291ac74b88b988c4ab07c16286942838ba4556~1
```

## Build
```bash
./gradlew :clients:compileJava :clients:compileTestJava -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet
```
