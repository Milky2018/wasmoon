# Shared native header dependency investigation

## Reproduced defect

On installed stable MoonBuild `0.1.20261012 (748b63c)`, two packages compile C
stubs that transitively include `producer/api.h` -> `producer/shared.h`.
Changing only the shared struct from 8 to 16 bytes recompiles the producer,
while the consumer still returns 8. [The failing incremental test](stable-header-only.log)
and [passing clean control](stable-clean-control.log) isolate stale objects.
The original Wasmoon ASan observation remains in
[ISS-625 evidence](../runtime-failures-2026-10-15/abi-cache-before.log).

The stable source registers package-local headers as C compilation inputs,
without requesting compiler dependency output. Cross-package includes therefore
never reach the incremental database. No supported package option was found
that declares the missing transitive header inputs; `native-stub` declares C
source files, not arbitrary headers.

Manual Wasmoon inventory identified shared includes in `native_test_support`,
`jit_ffi` (callable registry and Windows I/O), `host_io/wasi`, and
`host_io/reactor`. Header lifetime, struct size, inline functions, macros and
conditional platform code are all affected by the same dependency defect.

## Prepared upstream changes

- [MoonBuild patch](moonbuild.patch), against
  `748b63c25261be2ec38b2cc70884d5894a456360`: request GCC/Clang/TCC-compatible
  Makefile dependency output or MSVC/clang-cl `/showIncludes`, carry the discovery
  metadata through Execution Plan, and connect it to existing n2 support. Use the
  same mechanism for C stubs, native runtime objects and generated-C compilation.
  Set `VSLANG=1033` for the MSVC include prefix.
- [n2 patch](n2.patch), against
  `73429f6a8e6b7b5f5382e4cf98c0c2746ba4c6bd`: extend its existing depfile parser
  to decode escaped spaces/hash/dollar/colon, preserve ordinary Windows and UNC
  separators, and retain UTF-8 paths. Directly enabling depfiles first exposed
  the failure on `shared abi.inc`. Tests also cover odd/even backslashes and CRLF.
- Dynamic includes are not represented by the pure global action identity.
  Mark actions requesting discovery cache-ineligible until that identity can
  validate the full closure on cold and warm builds. Global artifact reads and
  writes are not currently connected to execution; this is a guarded future
  reuse boundary, not evidence of a present global-cache hit.

These are local, uncommitted candidate patches, not changes installed in
`~/.moon/bin/moon`. The original Moon checkout and Cargo dependency cache sources
were not edited. Isolated worktrees are `/tmp/wasmoon-iss634-moon` and
`/tmp/wasmoon-iss634-n2`. The candidate MoonBuild locally uses the n2 worktree via
an ephemeral Cargo path override; that machine-specific override is intentionally
excluded from the portable patch. Upstream adoption must pin the accepted n2
revision instead. No upstream issue, commit, push or PR has been made.

## Verification boundary

- [MoonBuild regression](moonbuild-regression.log): debug and release runs cover
  header-only layout growth, same-length macro changes, replacement include
  edges, a shared `.inc` filename containing a space, and removed required headers.
- [Disabled-discovery mutation control](disabled-discovery-control.log): removing
  only the n2 wiring restores the 16-versus-8 failure; emitting a `.d` alone is
  insufficient.
- [Real Wasmoon integration](runtime.json): the final combined candidate passed
  163/163 instrumented tests both [before](runtime-baseline.log) and
  [after](runtime-header-only.log) a header-only growth of `jit_trap_activation_t`
  in an isolated workspace. Both `trap.o` and `context_test_support.o` were
  recompiled without editing their C sources or cleaning between runs; no
  ASan/UBSan error was reported. The record identifies the candidate binary and
  patches. This remains dirty local macOS evidence, not upstream or Windows CI.
- [No-op build](noop.json): both C objects retain their modification timestamps.
- MoonBuild [lowering/model unit tests](moonbuild-unit-tests.log): 99/99;
  [executor/cache identity tests](executor-unit-tests.log): 31/31;
  [n2 library tests](n2-unit-tests.log): 53/53.
- [Clippy](moonbuild-clippy.log): changed Moon crates pass with warnings denied;
  the n2 path dependency still emits pre-existing warnings from its old source
  under the current Rust compiler. Those diagnostics are retained, not suppressed.
- Three native-backend graph snapshot tests still expect commands without the
  newly added dependency flags (13 passed, 3 snapshot mismatches, 1 existing
  ignore). Snapshot reconciliation and full upstream/platform CI remain pending.
- Wasmoon stable [native tests](wasmoon-native-tests.log): 2721/2721;
  [Python tests](script-tests.log): 172 run, 54 existing platform skips.
- The stable sanitizer runner now discards only its private generated `build`
  directory when recreating the source workspace. Its [163/163 result](sanitizer-tests.log)
  and [instrumentation summary](sanitizer-summary.json) establish fresh macOS
  ASan/UBSan with both ASan controls. This does not fix ordinary incremental
  builds and is not Linux LSan acceptance. `install.sh` already rebuilds its
  private release directory from scratch.

ISS-634 remains in progress: the configured stable tool still lacks the root
fix, and Windows Clang/MSVC, Linux LSan and complete upstream acceptance are not
yet established. Clean builds are the supported temporary workaround.
