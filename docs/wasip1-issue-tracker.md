# WASIp1 Issue Tracker

Last updated: 2026-04-03

## Status Legend

- `TODO`: not started
- `IN_PROGRESS`: currently being fixed
- `BLOCKED`: blocked by platform/public API limitations or external dependency constraints
- `DONE`: fixed and verified locally

## Issues

| ID | Source | Problem | Status | Notes |
| --- | --- | --- | --- | --- |
| WASIP1-001 | `jit/jit_ffi/wasi.c` | High: `poll_oneoff` clock semantics are still not spec-correct in JIT (absolute clock handling and event emission coupling with `poll_result == 0`). | DONE | JIT `poll_oneoff` now keeps per-subscription clock-id semantics and emits expired clock events even when fd events are also ready. Locked by test `poll_oneoff keeps expired realtime clock when fd is ready` in `testsuite/wasi_jit_wbtest.mbt`. |
| WASIP1-002 | `wasi/context.mbt`, `wasi/functions.mbt`, `jit/jit_ffi/wasi.c` | High: rights/capability model is not enforced; fd rights are effectively “all rights”, and `fd_fdstat_set_rights` is a no-op. | IN_PROGRESS | `fd_fdstat_set_rights` aligned to wasmtime (`ENOTSUP` valid fd / `EBADF` invalid). `fd_fdstat_get` now derives rights per descriptor type/access mode and includes preopen directory base/inheriting rights matching wasmtime-style behavior in both interpreter and JIT. Locked by `wasi/wasi_wbtest.mbt` and new JIT parity tests. Remaining gap: no explicit per-operation rights-deny path; behavior mainly follows host open mode + fd kind checks. |
| WASIP1-003 | `wasi/functions.mbt`, `jit/jit_ffi/wasi.c` | High: errno mapping is still coarse and inconsistent between interpreter/JIT; multiple failure paths collapse to `EIO`. | IN_PROGRESS | Expanded `errno -> WASI errno` mapping tables in both `wasi/ffi_native.c` and `jit/jit_ffi/wasi.c` to cover additional wasmtime-relevant cases (deadlock/quota/msgsize/notsock/notrecoverable/proto/timedout/etc.), reducing fallback-to-`EIO` cases and improving interpreter/JIT consistency. Remaining fallback for truly unknown host errno still maps to `EIO`. |
| WASIP1-004 | `wasi/functions.mbt` | High: interpreter `fd_renumber` semantics are unsafe (`dup2` target and fd-table bookkeeping are not fully coherent). | DONE | Reworked to descriptor-table move semantics (no `dup2` on WASI fd numbers), require existing `to` fd (`EBADF` on unused target), and keep preopen mapping coherent. Verified by `testsuite/wasi_jit_wbtest.mbt` test `fd_renumber rejects unused target with EBADF (8)`. |
| WASIP1-005 | `wasi/functions.mbt` | Medium: interpreter `fd_fdstat_set_flags` uses hardcoded native flag constants, which is cross-platform fragile. | DONE | Interpreter now rejects `DSYNC/RSYNC/SYNC` with `EINVAL` and toggles only `APPEND/NONBLOCK` using host constants from FFI. JIT side updated to same acceptance policy and preserves existing `F_GETFL` bits. Verified by `fd_fdstat_set_flags rejects DSYNC with EINVAL (28)`. |
| WASIP1-006 | `wasi/context.mbt`, `jit/jit_ffi/wasi.c` | Medium: preopen path confinement is lexical normalization + join, lacking capability-level symlink-safe containment. | TODO | Evidence: `wasi/context.mbt:344`, `wasi/context.mbt:391`, `jit/jit_ffi/wasi.c:203`, `jit/jit_ffi/wasi.c:303`. |
| WASIP1-007 | `wasi/functions.mbt` | Medium: accepted sockets are tracked as `CharacterDevice`, causing filetype reporting mismatch for socket fds. | DONE | `sock_accept_impl` now registers accepted sockets as `SocketStream`, and `fd_fdstat_get` reports socket stream (`filetype=6`). Covered by `wasi/wasi_wbtest.mbt` synthetic socket fd assertion. |
| WASIP1-008 | `wasi/functions.mbt`, `jit/jit_ffi/wasi.c` | Medium: interpreter has weaker explicit guest-memory bounds validation than JIT (`EFAULT` parity risk, trap behavior differences). | IN_PROGRESS | Added explicit `check_mem_range`/`check_iovecs_mem_range` validation and `EFAULT` returns for critical paths (`fd_write/read/pread/pwrite`, `poll_oneoff`, multiple path APIs, socket recv/send/accept, fdstat/filestat/prestat/random/args_sizes). Added regression tests in `wasi/wasi_wbtest.mbt` and parity tests in `testsuite/wasi_jit_wbtest.mbt`. Remaining gap: not yet every WASI entrypoint is fully audited for pointer-range parity. |

## Current Work Queue

- WASIP1-002 (`IN_PROGRESS`)
- WASIP1-003 (`IN_PROGRESS`)
- WASIP1-006 (`TODO`)
- WASIP1-008 (`IN_PROGRESS`)
