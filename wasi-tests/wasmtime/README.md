# Wasmtime WASIp1 guest programs

This snapshot imports all 58 `p1_*.rs` guest programs from Wasmtime commit
[`668016926adfd1b8a79dbce894f1e203d8892599`](https://github.com/bytecodealliance/wasmtime/tree/668016926adfd1b8a79dbce894f1e203d8892599/crates/test-programs/src/bin).
The guest sources and `preview1.rs` support module are unchanged. The small
local Cargo manifest builds just these programs, with the upstream snapshot's
`wasip1` and `libc` versions pinned in `Cargo.lock`. Other Wasmtime dependencies
and the Wasmtime runtime itself are not required.

## Run

From the Wasmoon repository root, with Python 3.11+ and Rust 1.85+ installed:

```sh
rustup target add wasm32-wasip1
./install.sh
python3 scripts/run_wasmtime_p1.py
```

The default runs both interpreter and JIT. Each invocation has a 30-second
timeout. Filter individual programs or run an independent Wasmtime CLI:

```sh
python3 scripts/run_wasmtime_p1.py --list
python3 scripts/run_wasmtime_p1.py --check
python3 scripts/run_wasmtime_p1.py --filter 'p1_poll*' --mode interp
python3 scripts/run_wasmtime_p1.py --mode wasmtime --wasmtime /path/to/wasmtime
python3 scripts/run_wasmtime_p1.py --output tmp/p1-results --timeout 60
python3 scripts/run_wasmtime_p1.py --profile explicit-rights
```

The default profile uses the unchanged sources. The `explicit-rights` profile
applies `explicit-rights.patch` to a temporary copy, uses a separate build
directory and records the patch hash and profile in each report.

The runner verifies the complete upstream file inventory and hashes before
building with `cargo build --locked`. No source downloads are needed; Cargo
fetches the two locked dependencies on the first build. Build products go under
`target/wasmtime-p1-build`. Results go to a unique directory under
`target/wasmtime-p1-results`, unless `--output` specifies a new or empty directory.
Existing evidence is never overwritten. Use the same Rust toolchain to reproduce
guest binaries; CI pins Rust 1.97.0. Reports include the compiler version, host,
engine path/version/hash, upstream commit, Cargo lock hash, commands and per-guest
Wasm hashes. The engine must be freshly built separately after runtime changes.

## Host contracts and verdicts

The upstream host references are retained under `upstream/crates/wasi/tests/all`
and `upstream/crates/test-programs/artifacts/src/lib.rs`.

- Every program gets a fresh read-write scratch directory preopened as `.` and
  receives `.` as its first argument. Scratch contents are removed after each
  invocation; logs remain. Re-run by program name to recreate its fixture.
- `ERRNO_MODE_MACOS=1` or `ERRNO_MODE_UNIX=1` follows the upstream host platform.
  The runner does not force permissive errno matching or disable guest checks.
- Standard streams are captured to files, with EOF stdin, except the terminal
  case, which receives a real PTY for all three descriptors. PTY output merges
  stdout and stderr into `stdout.txt`.
- `p1_poll_oneoff_stdio` runs twice: EOF stdin and an open, unreadable pipe.
  Thus 58 programs produce 59 reported scenarios per engine/mode.
- `p1_stat_extreme_host_mtime` gets the upstream `extreme.dat` contents and a
  best-effort extreme negative timestamp. As upstream, a host filesystem may
  reject or clamp the timestamp.
- `p1_cli_much_stdout` receives `hello, world!` and `10000`; its complete output
  must equal the expected 130,000 bytes. Other guests carry their own assertions.
- Nonzero exits (including guest assertion traps or host crashes), timeouts and
  harness errors remain failures. There is no expected-failure list. Exit status
  is 0 when all executed tests pass, 1 for guest failures/timeouts or no executed
  successes, and 2 for harness/setup errors. Unsupported cases are counted
  separately and never count as passes. A successful exit does not imply full
  suite coverage; inspect the unsupported count.

Four programs are explicitly unsupported by this CLI harness:

| Program | Missing contract |
| --- | --- |
| `p1_cli_hostcall_fuel` | Wasmtime-specific hostcall resource limits |
| `p1_file_truncation_readonly` | Read-only preopen capability |
| `p1_file_hardlink_across_perms` | Read-only preopen capability |
| `p1_file_rename_across_perms` | Read-only preopen capability |

These exclusions also apply to `--mode wasmtime`, so the reference run uses the
same coverage. Host `chmod` is not a substitute for a read-only WASI preopen.
The runner does not reproduce Wasmtime's host API or table-capacity limits.
It targets macOS and Linux, not Windows.

## Initial results and interpretation

On macOS ARM64, with Rust 1.97.0 and Wasmoon `1a33cb08` rebuilt from source:

| Engine/mode | Pass | Fail | Unsupported | Timeout |
| --- | ---: | ---: | ---: | ---: |
| Wasmoon interpreter | 11 | 44 | 4 | 0 |
| Wasmoon JIT | 11 | 44 | 4 | 0 |
| Wasmtime 40.0.0 | 54 | 1 | 4 | 0 |

The Wasmtime reference is older than the source snapshot. Its one failure is a
host panic on the extreme timestamp fixture; this is not an expected guest
failure and remains red in the report.

After the P1 fixes, the unchanged profile has 13 passes, 42 failures and four
unsupported scenarios per engine. Both stdio polling variants now pass.

The separate `explicit-rights` profile requests missing operation rights in a
temporary source copy. It preserves every guest assertion and the original
snapshot. On macOS ARM64 it has 53 passes, two failures, four unsupported
scenarios and no timeouts in each engine. The two remaining failures are
`p1_file_write` and `p1_path_open_read_write`: their error assertions exclude
`NOTCAPABLE` when an intentionally absent read/write capability is required.
They remain red. See the [rights decision](../../docs/wasip1-rights.md).

The recovered coverage exposed and now guards polling ABI alignment, Darwin
device readiness, directory cursor isolation and heap safety, byte-oriented
UTF-8 readlink/readdir output, trailing-slash constraints and positioned append
behavior. Independent ABI probes and a retained native AddressSanitizer test
cover the fixes. Linux results must be verified by the platform workflow;
macOS results are not evidence of Linux execution.

The regular CI checks the snapshot and Python runner tests. The separate
`Upstream WASIp1 programs` workflow is manually dispatched and runs both host
platforms, uploading logs even when tests fail. It intentionally remains a
strict, red diagnostic run while the current failures are unresolved; it does
not weaken the normal CI with a blanket expected-failure mask.

## Updating the snapshot

Select an exact upstream commit. Copy every `crates/test-programs/src/bin/p1_*.rs`,
`crates/test-programs/src/preview1.rs`, the three host reference files listed in
`SNAPSHOT.json`, and `LICENSE` without modifying them. Refresh their SHA-256
entries and the Cargo binary inventory. Re-audit host fixtures and exclusions,
pin dependencies against the upstream Cargo lock, regenerate the local lock,
then run the snapshot check, runner tests and all guest scenarios. Do not update
hashes simply to accept a local assertion change.

License: [Apache-2.0 WITH LLVM-exception](upstream/LICENSE).
