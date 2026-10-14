FROM bug-bench/base-cpp

# iptables is kept for interactive network-fault experiments (no case oracle requires it).
# Go is needed for running kvrocks Go integration tests (kvrocks-2520).
# locales is needed so cmake can extract zip archives with UTF-8 paths (pegtl).
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    autoconf \
    locales \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Install Go (needed for kvrocks Go integration tests)
COPY --from=bug-bench/base-go /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

