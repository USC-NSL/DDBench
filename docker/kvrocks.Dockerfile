FROM bug-bench/base-cpp

# Kvrocks needs iptables for the replication-wal case (kvrocks-3356).
# Install it in the image so bench.sh only needs --cap-add=NET_ADMIN at runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    && rm -rf /var/lib/apt/lists/*
