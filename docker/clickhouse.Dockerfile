FROM bug-bench/base-cpp

# Install clang-23 from LLVM versioned repo (pinned to clang-23 channel)
RUN apt-get update && apt-get install -y --no-install-recommends lsb-release && \
    wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc >/dev/null && \
    echo "deb http://apt.llvm.org/$(lsb_release -cs)/ llvm-toolchain-$(lsb_release -cs)-23 main" \
        > /etc/apt/sources.list.d/llvm.list && \
    apt-get update && apt-get install -y --no-install-recommends \
        clang-23 lld-23 \
        default-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# Install rustup (Rust nightly toolchain will be installed at setup time,
# pinned to the version required by the specific ClickHouse commit)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
