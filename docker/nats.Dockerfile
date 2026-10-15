FROM bug-bench/base-go

# nats CLI, pinned (contemporary with the nats-server releases in the corpus).
# It lives in the image, outside the agent-editable worktree, so oracles that
# drive a live cluster with it (nats-7760) always get the same, unmodified tool.
# natscli needs Go >= 1.24; the build toolchain is pinned as well.
ARG NATSCLI_VERSION=v0.3.0
RUN GOBIN=/usr/local/bin GOTOOLCHAIN=go1.26.9 go install github.com/nats-io/natscli/nats@${NATSCLI_VERSION} \
    && rm -rf /root/go/pkg/mod /root/.cache/go-build \
    && nats --version
