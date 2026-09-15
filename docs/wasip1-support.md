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
| `clock_res_get` | Policy/implementation review | ISS-535 | CPU clocks, host yield and opt-in signal delivery need explicit contracts. |
| `clock_time_get` | Policy/implementation review | ISS-535 | CPU clocks, host yield and opt-in signal delivery need explicit contracts. |
| `environ_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `environ_sizes_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_advise` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_allocate` | Incomplete | ISS-533 | Allocation, sync flags or shared-offset semantics require implementation. |
| `fd_close` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_datasync` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_fdstat_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_fdstat_set_flags` | Incomplete | ISS-533 | Allocation, sync flags or shared-offset semantics require implementation. |
| `fd_fdstat_set_rights` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_filestat_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_filestat_set_size` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_filestat_set_times` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_pread` | Incomplete | ISS-533 | Allocation, sync flags or shared-offset semantics require implementation. |
| `fd_prestat_dir_name` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_prestat_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_pwrite` | Incomplete | ISS-533 | Allocation, sync flags or shared-offset semantics require implementation. |
| `fd_read` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_readdir` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_renumber` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_seek` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_sync` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_tell` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `fd_write` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `path_create_directory` | Migration required | ISS-532 | Replace ambient path use; preserve lookup flags, rights and leaf semantics. |
| `path_filestat_get` | Migration required | ISS-532 | Replace ambient path use; preserve lookup flags, rights and leaf semantics. |
| `path_filestat_set_times` | Migration required | ISS-532 | Replace ambient path use; preserve lookup flags, rights and leaf semantics. |
| `path_link` | Migration required | ISS-532 | Replace ambient path use; preserve lookup flags, rights and leaf semantics. |
| `path_open` | Migration required | ISS-532 | Replace ambient path use; preserve lookup flags, rights and leaf semantics. |
| `path_readlink` | Migration required | ISS-532 | Replace ambient path use; preserve lookup flags, rights and leaf semantics. |
| `path_remove_directory` | Migration required | ISS-532 | Replace ambient path use; preserve lookup flags, rights and leaf semantics. |
| `path_rename` | Migration required | ISS-532 | Replace ambient path use; preserve lookup flags, rights and leaf semantics. |
| `path_symlink` | Migration required | ISS-532 | Replace ambient path use; preserve lookup flags, rights and leaf semantics. |
| `path_unlink_file` | Migration required | ISS-532 | Replace ambient path use; preserve lookup flags, rights and leaf semantics. |
| `poll_oneoff` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `proc_exit` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `proc_raise` | Policy/implementation review | ISS-535 | CPU clocks, host yield and opt-in signal delivery need explicit contracts. |
| `random_get` | Implemented; baseline coverage | ISS-536 | Audit bounds, errors, rights and applicable descriptor kinds; retain external regressions. |
| `sched_yield` | Policy/implementation review | ISS-535 | CPU clocks, host yield and opt-in signal delivery need explicit contracts. |
| `sock_accept` | Missing operation | ISS-534 | Currently returns NotSup after validation; add host-provided sockets and complete flags. |
| `sock_recv` | Missing operation | ISS-534 | Currently returns NotSup after validation; add host-provided sockets and complete flags. |
| `sock_send` | Missing operation | ISS-534 | Currently returns NotSup after validation; add host-provided sockets and complete flags. |
| `sock_shutdown` | Missing operation | ISS-534 | Currently returns NotSup after validation; add host-provided sockets and complete flags. |

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
