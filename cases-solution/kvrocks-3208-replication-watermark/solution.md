# Solution: Kvrocks #3208

- **Issue:** https://github.com/apache/kvrocks/issues/3208
- **Fix commit:** [`54929cd01603f9a19cd3b700b8b4da1683e4eda9`](https://github.com/apache/kvrocks/commit/54929cd01603f9a19cd3b700b8b4da1683e4eda9)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/apache/kvrocks/pull/3243
- **Commit:** `54929cd01603f9a19cd3b700b8b4da1683e4eda9`

## Fix locus
- **Component:** Replication stream parser (incremental replication callback)
- **Files:** `src/cluster/replication.cc` (+4/-0)

## Root cause
The replication callback uses libevent's `bufferevent_setwatermark()` to set the read watermark based on the expected data size when receiving a large RESP bulk string. This optimization avoids unnecessary callback invocations for partial data. However, after reading the complete bulk data and returning `CBState::AGAIN`, the watermark is not reset to 0. Consequently, the next callback invocation (e.g., for a small PING or a short command) will not fire until enough bytes accumulate to meet the stale high watermark, causing the replica to stall.

## Diagnosis chain
1. **Runtime observation:** The replica shows `master_link_status:up` but replication offset lags behind the master. No errors in logs. Restarting either side fixes the issue.
2. **Pattern recognition:** The stall occurs specifically after a large batch of data, and small subsequent writes are delayed. This points to a buffering or threshold issue in the replication data path.
3. **Code reasoning:** The replication callback in `replication.cc` sets `bufferevent_setwatermark(bev, EV_READ, size, 0)` when it expects a large bulk string, so libevent won't call back until `size` bytes are available. After reading the data, the callback returns `CBState::AGAIN` but does NOT reset the watermark. The next iteration of the callback loop expects a new RESP line, but libevent won't invoke the callback until the previous (stale) watermark threshold is met.
4. **Fix:** Add `bufferevent_setwatermark(bev, EV_READ, 0, 0)` after successfully reading each bulk string, resetting the threshold for the next protocol element.

## Fix description
The fix adds two `bufferevent_setwatermark(bev, EV_READ, 0, 0)` calls — one after reading a complete inline bulk string and one after reading a complete bulk data payload. These reset the libevent read watermark to zero so that the callback fires for any subsequent data, regardless of size.

## How to apply
```bash
git checkout 54929cd01603f9a19cd3b700b8b4da1683e4eda9
git submodule update --init --recursive
mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Debug && make -j$(nproc)
```

## How to verify
Run `reproduce.sh` — should print `PASS: Bug is fixed`.
