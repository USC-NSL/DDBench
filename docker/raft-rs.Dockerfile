FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl build-essential pkg-config libssl-dev cmake protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Rust toolchain, pinned: rustup-init is downloaded by version and verified
# against a fixed SHA-256, then installs a fixed Rust release.
ARG RUSTUP_VERSION=1.29.1
ARG RUST_TOOLCHAIN=1.99.0
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
        amd64) triple=x86_64-unknown-linux-gnu;  sha=dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71 ;; \
        arm64) triple=aarch64-unknown-linux-gnu; sha=15f6e4ce9f583b929c996c91562bad6d4454f3281de858b02cdfdef615fac433 ;; \
        *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/rustup-init \
        "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${triple}/rustup-init"; \
    echo "${sha}  /tmp/rustup-init" | sha256sum -c -; \
    chmod +x /tmp/rustup-init; \
    /tmp/rustup-init -y --no-modify-path --default-toolchain "${RUST_TOOLCHAIN}"; \
    rm /tmp/rustup-init
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /workspace
