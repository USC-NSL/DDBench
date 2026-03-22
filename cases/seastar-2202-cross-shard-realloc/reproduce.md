# Reproduce: Seastar #2202

## Prerequisites
A built Seastar development environment (see setup.md).

## Step 1: Write a test case

Create a file `test_cross_shard_realloc.cc`:
```cpp
#include <seastar/core/app-template.hh>
#include <seastar/core/smp.hh>
#include <seastar/core/memory.hh>
#include <cstdlib>

using namespace seastar;

int main(int argc, char** argv) {
    app_template app;
    return app.run(argc, argv, [] {
        return smp::invoke_on(0, [] {
            // Allocate 1024 bytes on shard 0
            void* ptr = malloc(1024);
            memset(ptr, 'A', 1024);
            return reinterpret_cast<uintptr_t>(ptr);
        }).then([](uintptr_t addr) {
            return smp::invoke_on(1, [addr] {
                void* ptr = reinterpret_cast<void*>(addr);
                // Realloc to SMALLER size on shard 1 => assertion crash
                void* new_ptr = realloc(ptr, 128);
                if (new_ptr) {
                    free(new_ptr);
                }
                return make_ready_future<>();
            });
        }).then([] {
            fmt::print("PASS: cross-shard realloc succeeded\n");
            return make_ready_future<>();
        });
    });
}
```

## Step 2: Build and run

```bash
# Add to CMakeLists or compile manually:
c++ -std=c++20 test_cross_shard_realloc.cc \
    $(pkg-config --cflags --libs seastar) \
    -o test_cross_shard_realloc

./test_cross_shard_realloc --smp 2
```

Alternatively, use `SEASTAR_TEST_CASE` in the existing test framework:
```cpp
SEASTAR_TEST_CASE(test_cross_shard_realloc_shrink) {
    auto ptr = co_await smp::invoke_on(0, [] {
        return reinterpret_cast<uintptr_t>(malloc(1024));
    });
    co_await smp::invoke_on(1, [ptr] {
        void* p = reinterpret_cast<void*>(ptr);
        void* np = realloc(p, 128);  // shrink on different shard
        free(np);
    });
}
```

## Expected result (bug present)
The process crashes with:
```
Assertion `object_cpu_id(ptr) == cpu_id' failed.
```
