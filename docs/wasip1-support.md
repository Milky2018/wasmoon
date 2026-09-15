# WASIp1 implementation and acceptance ledger

This is a source inventory, not a claim that every platform behavior is complete.
The registered `wasi_snapshot_preview1` imports are listed below. Runtime policy,
OS limitations, missing implementation and missing evidence are distinct states.

## Platform baseline

The current CI covers Linux AMD64, macOS ARM64 and Windows AMD64 (Clang and MSVC).
Both engines use the same P1 hostcall implementation. Windows permission probes
use Server 2025 (10.0.26100); this does not establish all Windows version or
filesystem combinations. ISS-536 owns the final matrix and exclusion audit.

## Imports

| Import | Status | Owner | Required review |
| --- | --- | --- | --- |
| `args_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `args_sizes_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `clock_res_get` | Implemented; CI pending | ISS-535 | Native CPU clocks and host yield; explicit host signal policy. |
| `clock_time_get` | Implemented; CI pending | ISS-535 | Native CPU clocks and host yield; explicit host signal policy. |
| `environ_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `environ_sizes_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_advise` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_allocate` | Implemented; cross-platform acceptance pending | ISS-533 | Allocation, logical cursors, append and synchronization have local coverage. |
| `fd_close` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_datasync` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_fdstat_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_fdstat_set_flags` | Implemented; cross-platform acceptance pending | ISS-533 | Allocation, logical cursors, append and synchronization have local coverage. |
| `fd_fdstat_set_rights` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_filestat_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_filestat_set_size` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_filestat_set_times` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_pread` | Implemented; cross-platform acceptance pending | ISS-533 | Allocation, logical cursors, append and synchronization have local coverage. |
| `fd_prestat_dir_name` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_prestat_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_pwrite` | Implemented; cross-platform acceptance pending | ISS-533 | Allocation, logical cursors, append and synchronization have local coverage. |
| `fd_read` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_readdir` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_renumber` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_seek` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_sync` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_tell` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_write` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `path_create_directory` | Implemented; cross-platform acceptance pending | ISS-532 | Held-directory operations and shared engine dispatch; verify race and permission matrix. |
| `path_filestat_get` | Implemented; cross-platform acceptance pending | ISS-532 | Held-directory operations and shared engine dispatch; verify race and permission matrix. |
| `path_filestat_set_times` | Implemented; cross-platform acceptance pending | ISS-532 | Held-directory operations and shared engine dispatch; verify race and permission matrix. |
| `path_link` | Implemented; cross-platform acceptance pending | ISS-532 | Held-directory operations and shared engine dispatch; verify race and permission matrix. |
| `path_open` | Implemented; cross-platform acceptance pending | ISS-532 | Held-directory operations and shared engine dispatch; verify race and permission matrix. |
| `path_readlink` | Implemented; cross-platform acceptance pending | ISS-532 | Held-directory operations and shared engine dispatch; verify race and permission matrix. |
| `path_remove_directory` | Implemented; cross-platform acceptance pending | ISS-532 | Held-directory operations and shared engine dispatch; verify race and permission matrix. |
| `path_rename` | Implemented; cross-platform acceptance pending | ISS-532 | Held-directory operations and shared engine dispatch; verify race and permission matrix. |
| `path_symlink` | Implemented; cross-platform acceptance pending | ISS-532 | Held-directory operations and shared engine dispatch; verify race and permission matrix. |
| `path_unlink_file` | Implemented; cross-platform acceptance pending | ISS-532 | Held-directory operations and shared engine dispatch; verify race and permission matrix. |
| `poll_oneoff` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `proc_exit` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `proc_raise` | Implemented; CI pending | ISS-535 | Native CPU clocks and host yield; explicit host signal policy. |
| `random_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `sched_yield` | Implemented; CI pending | ISS-535 | Native CPU clocks and host yield; explicit host signal policy. |
| `sock_accept` | Implemented; CI pending | ISS-534 | Host-injected stream/datagram sockets, rights and P1 flags. |
| `sock_recv` | Implemented; CI pending | ISS-534 | Host-injected stream/datagram sockets, rights and P1 flags. |
| `sock_send` | Implemented; CI pending | ISS-534 | Host-injected stream/datagram sockets, rights and P1 flags. |
| `sock_shutdown` | Implemented; CI pending | ISS-534 | Host-injected stream/datagram sockets, rights and P1 flags. |

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

- Local native tests, public hostcall regressions, and JIT/interpreter guest tests
  cover separate layers; passing one does not establish the others.
- Preserve the pinned upstream Wasmtime P1 sources and record all fixture
  adaptations. The Windows environment currently sets ERRNO_MODE_WINDOWS,
  NO_DANGLING_FILESYSTEM, NO_RENAME_DIR_TO_EMPTY_DIR and RENAME_DIR_ONTO_FILE;
  ISS-536 must audit the conditions each flag omits rather than counting them as
  coverage. Unix errno profiles also need explicit documentation.
- `p1_cli_hostcall_fuel` is a Wasmtime-specific policy excluded by agreement. Its
  two engine results are one excluded program, not two missing P1 capabilities.
- The explicit-rights runner includes read-only cases for Wasmoon. The reference
  Wasmtime CLI cannot express those preopen permissions; reference exclusions
  must not be confused with Wasmoon exclusions.
- Resource exhaustion, failure cleanup and deterministic directory replacement
  tests are required in addition to normal filesystem/socket success paths.

## Completion

ISS-530 is complete only when its children have evidence-backed close notes,
all supported behaviors pass the platform matrix, and each remaining limitation
is classified and documented. Full corpus success alone is not completion.

## Capability migration evidence

The Unix JIT previously selected a separate native C P1 implementation. A new
black-box guest reproduced mutation of a file outside the preopen while a host
thread replaced an ancestor with a symlink. P1 now uses the existing hostcall
bridge on every platform, including descriptor lookup for `poll_oneoff`.

Path entry operations hold the resolved parent directory. Open and metadata
operations share the beneath walker, including final symlink expansion. The
metadata mutation itself remains nofollow if the leaf changes concurrently.
Diagnostic `resolve_path` strings are no longer used to authorize P1 I/O.

Local macOS acceptance: 116 upstream explicit-rights cases passed across both
engines; four race scenarios covered ancestor and final-leaf replacement without
changing the outside file. Cross-platform CI acceptance remains pending.

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
EOF, half-close and nonblocking status are delegated to the native socket backend.
Readiness uses the same descriptors. Local TCP/UDP guest tests run through both
engines; Windows acceptance remains pending.

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
