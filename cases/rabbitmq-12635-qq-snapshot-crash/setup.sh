#!/usr/bin/env bash
# Setup script for rabbitmq-12635-qq-snapshot-crash
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
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/rabbitmq-12635-qq-snapshot-crash"
BUGGY_COMMIT="889fdc9163a43207f80a578769486bcce909f129"
REPO_URL="https://github.com/rabbitmq/rabbitmq-server.git"

echo "=== Setting up rabbitmq-12635-qq-snapshot-crash ==="

# RabbitMQ 4.0 requires Erlang/OTP 26+ and Elixir 1.17+.
# Ubuntu 24.04 ships OTP 25 which is insufficient.
# Check if OTP 26+ is available on the system.
OTP_VER=""
if command -v erl &>/dev/null; then
    OTP_VER=$(erl -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' -noshell 2>/dev/null || echo "")
fi

if [ -z "$OTP_VER" ] || [ "${OTP_VER%%.*}" -lt 26 ] 2>/dev/null; then
    echo "ERROR: Erlang/OTP 26+ is required but not found (found: ${OTP_VER:-none})."
    echo "On Ubuntu 24.04, the system Erlang is OTP 25 which is too old."
    echo ""
    echo "Options:"
    echo "  1. Use Docker mode (recommended): ./bench.sh setup rabbitmq-12635-qq-snapshot-crash"
    echo "  2. Install Erlang 26 via kerl: https://github.com/kerl/kerl"
    echo "  3. Install Erlang 26 via asdf: https://github.com/asdf-vm/asdf-erlang"
    exit 1
fi

if ! command -v elixir &>/dev/null; then
    echo "ERROR: Elixir is required but not found."
    echo "Install Elixir 1.17+ or use Docker mode."
    exit 1
fi

# Install build dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git make gcc g++ \
    python3 xsltproc xmlto zip unzip rsync

# Check prerequisites
for cmd in git erl elixir make; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

echo "Using Erlang/OTP $OTP_VER, Elixir $(elixir --version | tail -1)"

# Clone
if [ ! -d "$WORK_DIR" ]; then
    echo "Cloning repository..."
    git clone "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Checkout buggy version
echo "Checking out $BUGGY_COMMIT..."
git checkout "$BUGGY_COMMIT"

# Build
echo "Building RabbitMQ (this may take 10-20 minutes)..."
make -j"$(nproc)"

echo ""
echo "=== Setup complete ==="
echo "Workspace: $WORK_DIR"
