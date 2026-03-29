# Setup: raft-rs #345

## Project
- **Repository:** https://github.com/tikv/raft-rs
- **Language:** Rust
- **Issue:** https://github.com/tikv/raft-rs/issues/345

## Clone and checkout buggy version
```bash
git clone https://github.com/tikv/raft-rs.git
cd raft-rs
git checkout 513b82ce4507747a678fee7b4405c8b8b106fc12~1
```

## Build
```bash
cd harness
cargo test --no-run
```
