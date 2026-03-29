FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl build-essential pkg-config libssl-dev cmake protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Install Rust toolchain (stable, edition 2018 compatible)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /workspace
