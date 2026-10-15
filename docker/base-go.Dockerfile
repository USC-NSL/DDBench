# Go toolchain is copied from the official image rather than extracted from the
# release tarball. Streaming the tarball into a RUN layer
# (`curl ... | tar -C /usr/local -xz`) produces a layer that is fine *within* the
# RUN step but corrupt once committed: the next layer — and `docker run` on the
# resulting image — fails with
#   runc: exec "/bin/sh": stat /bin/sh: no such file or directory
# i.e. the whole rootfs is unusable. Reproduced on Docker 28.5.1 / overlay2 /
# extfs, independent of extraction path, and not size-related (a 75 MB
# single-file layer commits fine). COPY --from avoids it entirely.
# Go 1.23.6; base images are pinned by digest for reproducible builds. Cases
# whose go.mod asks for a newer toolchain get it via GOTOOLCHAIN=auto; setup
# caches it in the case's dependency volume.
FROM golang:1.23.6-bookworm@sha256:462f68e1109cc0415f58ba591f11e650b38e193fddc4a683a3b77d29be8bfb2c AS gotoolchain

FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl wget make gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=gotoolchain /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"

# Install Delve (Go debugger), pinned; it needs Go >= 1.25, so the build
# toolchain is pinned too (GOTOOLCHAIN would otherwise pick the newest release).
ARG DLV_VERSION=v1.27.2
RUN GOTOOLCHAIN=go1.26.9 go install github.com/go-delve/delve/cmd/dlv@${DLV_VERSION} \
    && rm -rf /root/go/pkg/mod /root/.cache/go-build

WORKDIR /workspace
