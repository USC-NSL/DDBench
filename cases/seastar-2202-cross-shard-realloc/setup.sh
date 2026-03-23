#!/usr/bin/env bash
# Setup script for seastar-2202-cross-shard-realloc
# Clones the repository, checks out the buggy commit, installs dependencies,
# builds Seastar, and compiles the test program.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/seastar-2202-cross-shard-realloc"
FIX_COMMIT="2bc4f22b"
REPO_URL="https://github.com/scylladb/seastar.git"

echo "=== Setting up seastar-2202-cross-shard-realloc ==="

# Install base dependencies
echo "Installing base build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake ninja-build git

# Check prerequisites
for cmd in git cmake ninja g++; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Clone
if [ ! -d "$WORK_DIR" ]; then
    echo "Cloning repository..."
    git clone "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Checkout parent of fix commit (buggy version)
echo "Checking out buggy commit (parent of $FIX_COMMIT)..."
git checkout "${FIX_COMMIT}~1" 2>/dev/null || git checkout $(git rev-parse "${FIX_COMMIT}~1")
git submodule update --init --recursive

# Install dependencies
echo "Installing dependencies..."
sudo ./install-dependencies.sh

# Build Seastar
if [ ! -d "$WORK_DIR/build/dev" ]; then
    echo "Configuring and building Seastar (this may take several minutes)..."
    ./configure.py --mode=dev --cook fmt
    ninja -C build/dev
else
    echo "Build directory already exists, skipping build."
fi

# Create test program
echo "Creating test program..."
cat > "$WORK_DIR/test_cross_shard_realloc.cc" <<'CPPEOF'
#include <seastar/core/app-template.hh>
#include <seastar/core/smp.hh>
#include <seastar/core/memory.hh>
#include <cstdlib>

using namespace seastar;

int main(int argc, char** argv) {
    app_template app;
    return app.run(argc, argv, [] {
        return smp::submit_to(0, [] {
            // Allocate 1024 bytes on shard 0
            void* ptr = malloc(1024);
            memset(ptr, 'A', 1024);
            return reinterpret_cast<uintptr_t>(ptr);
        }).then([](uintptr_t addr) {
            return smp::submit_to(1, [addr] {
                void* ptr = reinterpret_cast<void*>(addr);
                // Realloc to SMALLER size on shard 1 => assertion crash
                void* new_ptr = realloc(ptr, 128);
                if (new_ptr) {
                    free(new_ptr);
                }
                return make_ready_future<>();
            });
        }).then([] {
            fmt::print("cross-shard realloc succeeded\n");
            return make_ready_future<>();
        });
    });
}
CPPEOF

# Compile test program
echo "Compiling test program..."
c++ -std=c++20 "$WORK_DIR/test_cross_shard_realloc.cc" \
    $(pkg-config --cflags --libs "$WORK_DIR/build/dev/seastar.pc") \
    -o "$WORK_DIR/test_cross_shard_realloc"

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/test_cross_shard_realloc"
