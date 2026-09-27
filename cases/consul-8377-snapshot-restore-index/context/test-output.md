# Test Output

Obtained by running `go test -v -timeout 60s -run "TestStateStore_EnsureNode" ./agent/consul/state/` against the buggy build.

## Output

```
# github.com/hashicorp/consul/agent/consul/state
# [github.com/hashicorp/consul/agent/consul/state]
agent/consul/state/catalog_test.go:530:15: conversion from uint64 to string yields a string of one rune, not a string of digits
agent/consul/state/state_store_test.go:68:14: conversion from uint64 to string yields a string of one rune, not a string of digits
agent/consul/state/state_store_test.go:95:21: conversion from uint64 to string yields a string of one rune, not a string of digits
FAIL	github.com/hashicorp/consul/agent/consul/state [build failed]
```

Tests fail to compile due to Go toolchain version incompatibility (`uint64` to `string` conversion). This is a toolchain issue unrelated to the bug. The test files have no coverage for snapshot restore index preservation regardless.
