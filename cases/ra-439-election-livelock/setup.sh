#!/usr/bin/env bash
# Setup script for ra-439-election-livelock
# Clones the repository, checks out the buggy version, and builds the project.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/ra-439-election-livelock"
BUGGY_COMMIT="bdf8349a5515df5871e36918e8c5e1ee4c0011b3"
REPO_URL="https://github.com/rabbitmq/ra.git"

echo "=== Setting up ra-439-election-livelock ==="

# Ra requires Erlang/OTP 26+.
OTP_VER=""
if command -v erl &>/dev/null; then
    OTP_VER=$(erl -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' -noshell 2>/dev/null || echo "")
fi

if [ -z "$OTP_VER" ] || [ "${OTP_VER%%.*}" -lt 26 ] 2>/dev/null; then
    echo "ERROR: Erlang/OTP 26+ is required but not found (found: ${OTP_VER:-none})."
    echo "Use Docker mode: ./bench.sh setup ra-439-election-livelock"
    exit 1
fi

# Install build dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git make gcc g++ python3

# Clone
if [ ! -d "$WORK_DIR" ]; then
    echo "Cloning repository..."
    git clone "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Checkout buggy version
echo "Checking out $BUGGY_COMMIT..."
git checkout "$BUGGY_COMMIT"

# Build library and test dependencies
echo "Building ra library and fetching test dependencies..."
make -j"$(nproc)"
make test-deps

echo ""
echo "=== Setup complete ==="
echo "Workspace: $WORK_DIR"
