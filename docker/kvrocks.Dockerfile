FROM bug-bench/base-cpp

# Kvrocks needs iptables for the replication-wal case (kvrocks-3356).
# Go is needed for running kvrocks Go integration tests (kvrocks-2520).
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    && rm -rf /var/lib/apt/lists/*

# Install Go (needed for kvrocks Go integration tests)
COPY --from=bug-bench/base-go /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"
