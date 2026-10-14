# Verification: Kvrocks #3356

`reproduce.sh` is the oracle. It runs entirely inside the case container. It needs no root, no iptables and no extra Docker capabilities, and it uses only default server configuration.

## Test procedure

1. Start a master (port 13356) and a replica (port 13357). Wait until the replica is linked, and a sentinel key written on the master can be read on the replica.
2. Send `SIGSTOP` to the replica. It stops reading, but its TCP connection stays open (zero receive window).
3. Write 64 MB (256 × 256 KB `SET`s) to the master. This is far more than the loopback socket buffers can hold.
4. **Precondition:** the master's send queue on the replication connection, read from `/proc/net/tcp`, must be non-empty. If the master has already detached the replica, that also counts. If neither holds, the run is inconclusive and exits 2.
5. Keep a light write load on the master (one `SET` every 200 ms). Watch `INFO replication` for up to 90 s (`STALL_WINDOW`) to see whether the master still lists the replica.
6. If the master detached the replica: send `SIGCONT`, write a new sentinel, and require the replica to report `master_link_status:up` and return the sentinel within 90 s.

## Pass/fail criteria

- **FAIL (exit 1), bug present:** the master still lists the stalled replica after 90 s, its send queue is stuck, and nothing is logged. A master crash during the stall is also FAIL. So is a master that detaches the replica but where replication never recovers after the replica resumes.
- **PASS (exit 0), bug fixed:** the master detaches the stalled replica within 90 s, and replication recovers once the replica resumes.
- **ERROR (exit 2):** setup failed or the stall could not be established. This verdict is neither PASS nor FAIL.

## Why it is reliable

A frozen replica never reads, and its kernel keeps the connection alive. On the buggy build nothing ever ends the stall, so FAIL does not depend on timing or load. The send queue is checked before the 90 s window starts, so FAIL means the stall really happened. It can't be an artefact of too little data.

The window is generous on purpose. A fix that detects a dead consumer within any reasonable delay (up to about 60 s) passes. The oracle doesn't rely on any specific config option.

## Validation record

| Build | Runs | Verdict | Detail |
|---|---|---|---|
| Buggy (`559a667b~1`), earlier script wording | 5/5 | FAIL | send queue stuck at 2,428,800 B for the full 90 s |
| Buggy (`559a667b~1`), final script (incl. 1 end-to-end `bench.sh reproduce`) | 5/5 | FAIL | send queue stuck at 2,428,800 B for the full 90 s |
| Fixed (`559a667b`), incremental build | 9/9 | PASS | replica detached after about 30 s (`send timeout` logged); replication recovered |
| Fixed (`559a667b`), tree hash = `559a667b^{tree}`, clean build | 3/3 | PASS | same: detached after about 30 s; replication recovered |

Runtime: about 95 s for the buggy build and about 35 s for the fixed build, excluding the rebuild.
