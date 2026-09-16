# WASIp1 implementation and acceptance ledger

This records the implemented scope and its acceptance evidence, not a claim of
exhaustive platform equivalence.
The registered `wasi_snapshot_preview1` imports are listed below. Runtime policy,
OS limitations, missing implementation and missing evidence are distinct states.

## Platform baseline

The current CI covers Linux AMD64, macOS ARM64 and Windows AMD64 (Clang and MSVC).
Both engines use the same P1 hostcall implementation. Windows permission probes
use Server 2025 (10.0.26100); this does not establish all Windows version or
filesystem combinations. ISS-536 records the completed matrix and exclusion audit below.

## Imports

| Import | Status | Owner | Contract / evidence |
| --- | --- | --- | --- |
| `args_get` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `args_sizes_get` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `clock_res_get` | Implemented; matrix verified | ISS-535 | Native CPU clocks and host yield; explicit host signal policy. |
| `clock_time_get` | Implemented; matrix verified | ISS-535 | Native CPU clocks and host yield; explicit host signal policy. |
| `environ_get` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `environ_sizes_get` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_advise` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_allocate` | Implemented; matrix verified | ISS-533 | Allocation, logical cursors, append and synchronization have native and external coverage. |
| `fd_close` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_datasync` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_fdstat_get` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_fdstat_set_flags` | Implemented; matrix verified | ISS-533 | Allocation, logical cursors, append and synchronization have native and external coverage. |
| `fd_fdstat_set_rights` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_filestat_get` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_filestat_set_size` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_filestat_set_times` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_pread` | Implemented; matrix verified | ISS-533 | Allocation, logical cursors, append and synchronization have native and external coverage. |
| `fd_prestat_dir_name` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_prestat_get` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_pwrite` | Implemented; matrix verified | ISS-533 | Allocation, logical cursors, append and synchronization have native and external coverage. |
| `fd_read` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_readdir` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_renumber` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_seek` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_sync` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_tell` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `fd_write` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `path_create_directory` | Implemented; matrix verified | ISS-532 | Held-directory operations and shared engine dispatch; race and permission matrix passed. |
| `path_filestat_get` | Implemented; matrix verified | ISS-532 | Held-directory operations and shared engine dispatch; race and permission matrix passed. |
| `path_filestat_set_times` | Implemented; matrix verified | ISS-532 | Held-directory operations and shared engine dispatch; race and permission matrix passed. |
| `path_link` | Implemented; matrix verified | ISS-532 | Held-directory operations and shared engine dispatch; race and permission matrix passed. |
| `path_open` | Implemented; matrix verified | ISS-532 | Held-directory operations and shared engine dispatch; race and permission matrix passed. |
| `path_readlink` | Implemented; matrix verified | ISS-532 | Held-directory operations and shared engine dispatch; race and permission matrix passed. |
| `path_remove_directory` | Implemented; matrix verified | ISS-532 | Held-directory operations and shared engine dispatch; race and permission matrix passed. |
| `path_rename` | Implemented; matrix verified | ISS-532 | Held-directory operations and shared engine dispatch; race and permission matrix passed. |
| `path_symlink` | Implemented; matrix verified | ISS-532 | Held-directory operations and shared engine dispatch; race and permission matrix passed. |
| `path_unlink_file` | Implemented; matrix verified | ISS-532 | Held-directory operations and shared engine dispatch; race and permission matrix passed. |
| `poll_oneoff` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `proc_exit` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `proc_raise` | Implemented; matrix verified | ISS-535 | Native CPU clocks and host yield; explicit host signal policy. |
| `random_get` | Implemented; matrix verified | ISS-536 | Native ABI/rights regressions and external P1 gate; see acceptance record. |
| `sched_yield` | Implemented; matrix verified | ISS-535 | Native CPU clocks and host yield; explicit host signal policy. |
| `sock_accept` | Implemented; matrix verified | ISS-534 | Host-injected stream/datagram sockets, rights and P1 flags. |
| `sock_recv` | Implemented; matrix verified | ISS-534 | Host-injected stream/datagram sockets, rights and P1 flags. |
| `sock_send` | Implemented; matrix verified | ISS-534 | Host-injected stream/datagram sockets, rights and P1 flags. |
| `sock_shutdown` | Implemented; matrix verified | ISS-534 | Host-injected stream/datagram sockets, rights and P1 flags. |

## Cross-cutting contract

- Guest pointers and iovec ranges must be validated before native access. Size,
  offset and timestamp conversion must detect overflow and signedness errors.
- Directory operations require the corresponding base rights. Opened descriptors
  may receive only rights allowed by the parent's inheriting rights. Rights can
  be reduced, never regained by renumbering or changing flags.
- `path_open`: lookup flags 0..1, oflags mask 0x0f, fdflags mask 0x1f; directory,
  create, exclusive and truncate combinations require independent validation.
- `fd_fdstat_set_flags`: append, nonblock, dsync, rsync and sync must describe
  actual runtime behavior, including aliases. Positioned I/O must preserve the
  shared file cursor and handle append semantics explicitly (ISS-533).
- Path lookup follows guest components through held directory capabilities.
  Intermediate links, `..`, final-link policy, trailing separators and moved
  preopens must not revert to ambient path authority (ISS-532).
- Socket receive flags include peek and wait-all; datagram truncation is an
  output flag. Shutdown covers read, write and both. Host injection must establish
  descriptor kind, rights, ownership and blocking state (ISS-534).
- CPU clock identifiers and host signal delivery must have explicit platform and
  embedding policies. Unsupported host policy is not a silently successful call
  (ISS-535). `fd_advise` is advisory; acceptance does not require a measurable
  performance effect.

## Evidence and exclusions

- Native public hostcall regressions, disposable host-process probes, and
  JIT/interpreter guests exercise separate layers.
- The pinned upstream Wasmtime P1 sources remain unchanged. The capabilities
  profile records the rights adaptation and the two implemented-operation
  assertion changes, with source and guest hashes in each report.
- `p1_cli_hostcall_fuel` is a Wasmtime-specific policy excluded by agreement. Its
  two engine results are one excluded program, not two missing P1 capabilities.
- Read-only cases run for Wasmoon. The reference Wasmtime CLI cannot express
  those per-preopen permissions; its exclusions are not Wasmoon exclusions.
- Platform-guarded assertions are itemized below. They do not establish omitted
  behavior even when the containing guest exits successfully.

## Completion

ISS-530 and its children are closed with the acceptance evidence below. The
approved implementation scope passes the platform matrix; remaining policy,
compatibility and host limitations are documented separately from pass counts.

## Capability migration evidence

The Unix JIT previously selected a separate native C P1 implementation. A new
black-box guest reproduced mutation of a file outside the preopen while a host
thread replaced an ancestor with a symlink. P1 now uses the existing hostcall
bridge on every platform, including descriptor lookup for `poll_oneoff`.

Path entry operations hold the resolved parent directory. Open and metadata
operations share the beneath walker, including final symlink expansion. The
metadata mutation itself remains nofollow if the leaf changes concurrently.
Diagnostic `resolve_path` strings are no longer used to authorize P1 I/O.

Final acceptance: 116 capabilities-profile scenarios passed across both engines
on every matrix entry. Four race scenarios per entry covered ancestor and
final-leaf replacement without changing the outside file.

## File semantics

P1 owns its logical cursor in `OpenFile`. Ordinary positioned reads/writes use
native pread/pwrite; APPEND uses the host atomic append operation. `fd_pwrite`
never changes the logical cursor, including APPEND on macOS and Windows.
Renumbering transfers the same descriptor state. Host descriptor cursor movement
is not the P1 cursor contract.

DSYNC, SYNC and RSYNC are stored in descriptor state. Writes flush before success;
RSYNC reads flush first. Platforms may implement data-only flushing with the
stronger full flush. This supports changing flags without reopening by a path or
pretending that F_SETFL can change immutable kernel open flags. Host flush errors
are returned. In particular, host ACLs can prevent flushing a read-only handle.

Allocation uses Linux fallocate, macOS F_PREALLOCATE, or Windows FileAllocationInfo,
then extends logical size where necessary. Unsupported filesystems return their
native error; a truncate-only fallback is not presented as physical allocation.
macOS rejects files with existing holes before mutation because F_PREALLOCATE
allocates from physical EOF and cannot guarantee a requested hole is filled.
Windows similarly rejects sparse or compressed files: FileAllocationInfo does
not establish allocation of an arbitrary logical range. Both return NOTSUP;
Linux keeps native range allocation via fallocate. A failed hole query also
returns its native error. Ordinary dense-file allocation remains supported.
The physical-allocation CI guest verifies content and cursor preservation,
actual allocated storage, and the explicit unsupported cases in both engines.
The macOS and Windows allocation/extension sequence is not atomic against an
independent host process concurrently changing file length. The runtime does not
promise serializability against unrelated host processes.

API references: [Apple fcntl](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fcntl.2.html),
[Windows allocation](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_allocation_info),
[Windows flushing](https://learn.microsoft.com/en-us/windows/win32/fileio/file-caching).

The capabilities external profile changes only the upstream NOTSUP expectations
for allocation and SYNC. The unchanged upstream and explicit-rights profiles
remain available; their failures on those two programs are intentional behavior
differences. See `wasi-tests/wasmtime/implemented-capabilities.patch`.

## Socket ownership and transfers

`WasiContext::take_socket` transfers ownership only on success. The guest receives
an explicit rights subset; accepting a connection derives its rights from the
listener's inheriting rights. Windows callers use adapter descriptors, not raw
Winsock handles. Datagram sends gather all iovecs into one message; receives
scatter one message and report truncation, including with PEEK. Stream WAITALL,
EOF, half-close and nonblocking status use the native socket backend. Stream peek
bytes are retained in the owned descriptor so PEEK|WAITALL works on Windows too;
readiness and renumbering preserve this queued input.
Readiness uses the same descriptors. TCP/UDP guest tests run through both engines
and passed the Linux, macOS, Windows Clang and Windows MSVC native gates.

Shared P1 `proc_exit` now unwinds guest execution via a typed host exit outcome.
The CLI regression places `unreachable` after the exit call to detect accidental
continuation as well as loss of the exit status.

## Process policy and CPU clocks

Process and thread CPU clocks return native CPU accounting and resolution, rather
than wall-clock time. `sched_yield` invokes the OS scheduler. Signal delivery is
disabled by default (`NOTSUP`). An embedder may install
`WasiContextBuilder::signal_handler`; the handler receives validated P1 tags and
may return a denial or explicitly call `raise_host_signal`. Native signal delivery
can terminate the whole hosting process. The CLI does not opt in. Windows supports
the CRT signal subset; unavailable signals return `NOTSUP`. Unix maps P1 tags to
native constants rather than assuming signal numbers are portable.

## Additional acceptance boundaries

Argument/environment tables and preopen names use UTF-8 byte lengths. Buffer
validation uses the same encoding as the write; embedded NUL is rejected.
Injected sockets also support `fd_read` and `fd_write`, preserving datagram
message boundaries and the same rights as `sock_recv`/`sock_send`.

CPU clock reads are supported. Polling CPU-clock deadlines retains the existing
Wasmtime compatibility contract: a single relative subscription is a duration
sleep; absolute or mixed CPU-clock subscriptions return `INVAL`. It does not
claim a native per-thread CPU timer facility.

P1 addresses are unsigned wasm32 offsets, including addresses at or above 2 GiB.
Range checks reject wraparound across the 4 GiB boundary. MoonBit host buffers
still have signed-Int lengths; individual materialized buffers are limited to
less than 2 GiB, independent of where their guest data resides.

## Platform-specific fixture coverage

The external P1 runner uses the pinned upstream platform environment, not a
per-test expected-failure list. The reported pass count includes programs whose
own platform guards omit assertions. In particular, on Windows:

| Upstream setting | Effect in the pinned P1 programs |
| --- | --- |
| `ERRNO_MODE_WINDOWS` | Selects Windows-specific errno assertions; Unix and macOS runs select their own errno profiles. |
| `NO_DANGLING_FILESYSTEM` | Omits the main bodies of `p1_dangling_fd`, `p1_dangling_symlink`, and `p1_symlink_loop`; also omits dangling/loop hardlink cases in `p1_path_link`, dangling creation in `p1_path_symlink_trailing_slashes`, and read-only descriptor timestamp updates in `p1_fd_filestat_set`. |
| `NO_RENAME_DIR_TO_EMPTY_DIR` | Retained upstream configuration; no P1 program in this snapshot calls its accessor. It does not remove an executed P1 assertion. |
| `RENAME_DIR_ONTO_FILE` | Requires directory-over-file rename success in `p1_path_rename`; Unix instead requires `NOTDIR`. |

These guards are not proof of omitted behavior, nor do the upstream flag names
establish that Windows universally lacks dangling symlinks. Wasmoon additionally
runs held-capability path regressions, concurrent ancestor/leaf replacement, and
Windows privilege/Developer Mode probes. Those tests establish their named
scenarios, not every filesystem or reparse-point configuration.

`path_link` with `SYMLINK_FOLLOW` retains the pinned Wasmtime compatibility
behavior (`INVAL`). Signals require an explicit embedder policy; sockets require
host injection because Preview 1 has no socket creation/connect imports.
Windows symlink creation uses a private privilege scope covering both handle
creation and reparse setup. It restores the original thread token and never adds
a privilege absent from the caller token. If neither the granted privilege nor
Developer Mode permits creation, the call returns a permission error.

The misc runner's `script_only` verdict means the module/action script completed
but contained no assertion commands. These entries are executed, not skipped,
and are reported separately from assertion-bearing passes.

## Acceptance record (2026-09-15)

Runtime revision: `393f05359fb7c4a4e6874d469ab5fcc3fb8d0405`.
[Platform workflow and downloadable evidence](https://github.com/Milky2018/wasmoon/actions/runs/34974451011).
The subsequent issue-closure commit changes documentation only.

| Platform | Native tests | P1 capabilities, both engines | Misc, both engines | Job |
| --- | ---: | --- | --- | --- |
| Linux AMD64 | 2469 passed | 116 passed; 2 not applicable | 692 passed; 72 script-only | Passed |
| macOS ARM64 | 2469 passed | 116 passed; 2 not applicable | 692 passed; 72 script-only | Passed |
| Windows AMD64 MSVC | 2469 passed | 116 passed; 2 not applicable | 692 passed; 72 script-only | Passed |
| Windows AMD64 Clang | 2469 passed | 116 passed; 2 not applicable | 692 passed; 72 script-only | Passed |

The four corpus reports have zero failures, timeouts, unsupported cases, or
harness errors. P1 has 58 upstream programs plus a second stdio scenario; fuel
is the one excluded program in each engine. Misc covers all 382 scripts in each
engine, including high-memory cases. Its 36 scripts without assertions account
for the 72 separate script-only results.

Both Windows compilers completed the 52-test native probe suite successfully
(49 passed; three mode-dependent probes were skipped in the default invocation
and rerun under explicit permission modes),
12 readiness guest scenarios, four capability-path race scenarios, and both
Developer Mode settings. Linux and macOS also passed all four path race scenarios.
Every race scenario recorded successful guest opens and actual host replacements
while retaining the outside file's bytes, size, and timestamp.

The workflow also gates CLI behavior, core WAST, and all three component suites
in both engines. Local full native validation passed 2469 tests. These results
establish the recorded matrix and scenarios; they do not claim exhaustive
coverage of every OS version, filesystem, device, or resource-exhaustion state.
