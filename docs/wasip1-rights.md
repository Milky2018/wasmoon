# WASIp1 requested rights and upstream compatibility

Wasmoon preserves the initial base and inheriting rights requested by
`path_open`. Zero means no rights. A directory with no `PATH_OPEN` capability
cannot open children; a parent's inheriting mask bounds both masks requested
for its children. `fd_fdstat_set_rights` can only reduce capabilities, and
attempted additions return `NOTCAPABLE`. This follows the
[legacy Preview 1 contract](https://github.com/WebAssembly/WASI/blob/a2b96e81c0586125cc4dc79a5be0b78d9a059925/legacy/preview1/docs.md#path_open).

The pinned Wasmtime implementation layers P1 over P2. Its `path_open` uses
`FD_READ` and `FD_WRITE` as access modes, ignores the inheriting mask, and does
not store full P1 rights masks. Its `fd_fdstat_set_rights` returns `NOTSUP`.
[Wasmtime source](https://github.com/bytecodealliance/wasmtime/blob/668016926adfd1b8a79dbce894f1e203d8892599/crates/wasi/src/p1.rs#L2054).
Consequently, Wasmtime's tests are valuable operation tests but are not an
independent authority for legacy rights semantics.

## Coverage profiles

The runner's default `upstream` profile executes the unchanged, hashed snapshot.
Its 42 filesystem failures per engine remain visible: the shared scratch
helper requests zero rights and then attempts operations requiring rights.

`--profile explicit-rights` applies the separately reviewed
[adaptation patch](../wasi-tests/wasmtime/explicit-rights.patch) to a temporary
source copy. It requests scratch rights bounded by the preopen and adds the
operation capabilities used at file-opening callsites. Secondary directories
receive the specific directory/inheriting rights needed by their tests.
It never grants an intentionally absent `FD_READ` or `FD_WRITE` capability.
Fixture behavior and pass/fail rules are unchanged. The only assertion
adaptations are the three access-denial expectations documented below.

Adapted sources and build artifacts are separate from the original profile.
The temporary source copy is removed after building; reports identify the
profile, patch hash and guest binary hashes. These results measure adapted
operation coverage, not unchanged upstream conformance.

`p1_file_write` and `p1_path_open_read_write` deliberately attempt I/O without
the corresponding right. Their original errno assertions exclude `NOTCAPABLE`
and remain unchanged in the `upstream` profile. In `explicit-rights`, the three
denied calls assert exactly `NOTCAPABLE`: a zero-length write, a nonempty write,
and a read. No alternative errno is accepted and the missing I/O right remains
absent. Additional observation rights allow verification that denied writes
leave size, contents and cursor unchanged; denied reads preserve the guest
buffer and cursor. The later read-write filestat assertion explicitly requests
its own `FD_FILESTAT_GET` right.

Both affected guests run their blocking and nonblocking variants. The adapted
profile is a legacy-rights regression gate, including all subsequent operation
assertions. Its errno expectations intentionally differ from Wasmtime's P2-backed
implementation; use `upstream` for unchanged Wasmtime compatibility comparisons.

The independent `wasi_rights_contract_wbtest.mbt` guest verifies zero rights,
positive requested rights, inheritance bounds, reduction and failed
re-addition through both execution engines. This validates the chosen boundary;
it is not a certification of every WASIp1 capability operation.
