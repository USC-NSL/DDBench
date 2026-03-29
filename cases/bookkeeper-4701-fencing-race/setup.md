# Setup: BookKeeper #4701

## Project
- **Repository:** https://github.com/apache/bookkeeper
- **Language:** Java (Maven)
- **PR:** https://github.com/apache/bookkeeper/pull/4701

## Clone and checkout buggy version
```bash
git clone https://github.com/apache/bookkeeper.git
cd bookkeeper
git checkout 44607a0e31ee8f979211eb5a4ef424de2871b92e~1
```

## Build
```bash
mvn -pl bookkeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```

This builds only `bookkeeper-server` and its upstream dependencies, skipping tests, checkstyle, spotbugs, rat, and javadoc to minimize build time (~5-10 minutes depending on network and CPU).
