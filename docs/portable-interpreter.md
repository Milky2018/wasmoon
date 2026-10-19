# Core interpreter on the wasm target

The unreleased workspace provides `Milky2018/wasmoon_runtime/runtime` and
`Milky2018/wasmoon_runtime/executor` on `native` and linear-memory `wasm`.
The interpreter executes guest WebAssembly instructions in MoonBit on both
backends. It does not compile the guest to host WebAssembly or call a native JIT.

## Run the embedding example

From the repository root, with the stable MoonBit toolchain:

```sh
moon run modules/wasmoon_runtime/examples/embedding --target wasm
```

The [example](../modules/wasmoon_runtime/examples/embedding/main.mbt) contains a
binary guest. It decodes and validates that binary, registers a typed host
callback, instantiates the guest, and invokes a checked `executor.Function`.
The guest stores and loads its argument, invokes the callback, and returns 43.
The example also verifies the callback argument, stored memory and budget
restoration. It uses `defer` for resource cleanup.

This new module is not part of the published 0.17.0 registry release yet. These
commands use workspace sources; they do not establish registry availability.

## Dependency and implementation boundaries

The native assembly now depends on the runtime:

```text
wasmoon (native product) -> wasmoon_jit -> wasmoon_runtime -> wasm_core
wasmoon -> wasmoon_runtime/executor -> wasmoon_runtime/runtime
```

Arrows point from consumers to their dependencies. Neither portable runtime
package imports the `wasmoon_jit` module or the native product module.

| Dependency | Shared semantics | Native implementation | wasm implementation |
| --- | --- | --- | --- |
| Memory | Guest address arithmetic, bounds, types and bulk-operation checks | Authoritative C descriptor shared with JIT | Authoritative mutable MoonBit byte array |
| Table | References, types, element operations and limits | Optional native table view | Managed array only |
| Store/GC | Function/instance identity, subtype registry, root worklist, rollback and guest continuations | C heap/exception/continuation integration when used | Existing `MarkSweepHeap`; no native execution state or snapshot registry |
| Resource budget | Units, admission and failure rollback | RC-owned C quota/reservation | Managed quota/reservation with explicit release |
| Host roots | Checked `RootedValue`, provenance and root leases | Existing C `CleanupOwner` finalizer | Managed cleanup owner, explicitly closed |
| Execution policy | Nested limits, safepoints, cancellation and stop precedence | Shared `control` package and native monotonic clock | Same policy and MoonBit host clock |
| Async calls | Existing explicit execution stack and continuation driver | `moonbitlang/async` native integration | That library's wasm integration under `moonrun` |

`#cfg` declarations and target-selected files implement the physical differences.
There is no storage vtable on each interpreter memory access. Native integration
primitives live under `wasmoon_runtime/native`; target selection excludes their C
bindings, C stubs and machine-stack implementation from wasm. Managed quota and
metadata implementations in those packages are ordinary MoonBit code. The
`wasm_milkir` dependency supplies shared native reference-encoding constants;
using these constants does not instantiate a compiler or generate guest code.

Store, table and memory target variants stay in their respective packages because
they implement one API and require access to the same private state. Guest
instruction dispatch, validation, explicit frames and continuation execution are
shared rather than maintained as two interpreters.

## Host requirements

The supported initial host is the installed stable **`moonrun`**. A wasm artifact
is not necessarily a standalone WASIp1 command. The actual example import list
is retained with its validation evidence.

- Environment access uses the `__moonbit_fs_unstable` string and environment
  functions, including the interpreter's GC stress configuration.
- Deadlines use `__moonbit_time_unstable.instant_now` and
  `instant_elapsed_as_secs_f64` when retained by linking.
- Example/diagnostic output uses MoonBit's `wasi_snapshot_preview1.fd_write`.
  This does not install WASI imports in the *guest* Store.
- Async embeddings additionally require the `moonbitlang/async` host imports
  for event buses, timers, cancellation, signals and worker cleanup. The tests
  execute these imports through `moonrun`. Debug test artifacts also use its
  `exception` host imports.
- The Core WAST command additionally uses `moonbitlang/x/fs` and `x/sys` for
  reading test files, arguments and exit status. File access belongs to that
  command; the embedding example reads its binary from a constant.

A synchronous call does not start an async event loop. Browser glue, generic
WASIp1 hosting, wasm-gc packaging and arbitrary custom hosts need separate host
integration and acceptance.

## Resource lifetimes

On wasm, dropping an ordinary MoonBit struct is **not** a native C finalizer.
Managed storage becomes reclaimable through the MoonBit runtime, but logical
quotas and guest GC roots require the existing explicit cleanup operations:

- Close a `Store` or its owning `Linker` with `defer`. This cancels parked guest
  work, invalidates borrowed handles, releases Store-owned roots and quotas,
  clears host callback cycles, and closes adopted memory/tables.
- Close each retained `RootedValue`, including reference results of
  `Function.call`/`call_async`. A `defer` enclosing the use is sufficient.
  Aliases share the root lifetime: close invalidates all aliases and is
  idempotent. Escaping a closed root does not revive it.
- Call `ResourceLease.release`, `GcRootLease.release`,
  `InstanceAdmission.cancel` or `ExecutionContinuation.cancel` when finished
  with manually managed admission/root/work tokens. Interpreter-owned tokens
  are cleaned up by the existing call, rollback and cancellation paths.
- Standalone budgeted `Memory` and `Table` values have `close` methods. Once
  adopted, their Store closes them. Do not manually close a resource while
  guest execution is using it.

These explicit operations also work on native. Native last-owner finalizers
remain intact, including independently retained native allocations that outlive
Store close. wasm exposes no native descriptor whose independent lifetime would
require retaining a closed Store's memory charge. A missed explicit wasm close
can keep a root/charge until its Store closes; automatic last-owner cleanup is
not promised on this target.

Quotas bound logical accepted resources, not process RSS. The wasm implementation
uses contiguous arrays with a per-memory capacity of `0x7fff_fff0` bytes. Smaller
memory64 instances retain checked 64-bit addresses; unsupported capacities fail
allocation/growth rather than truncate addresses. Host/allocator exhaustion can
still terminate a process or trap a wasm host and is not a recoverable guest
resource-budget error.

## Capability matrix

| Capability | wasm interpreter |
| --- | --- |
| Integers, floats, conversions, SIMD and relaxed SIMD | Supported |
| Function references, indirect/ref calls and tail calls | Supported |
| GC structs/arrays, exceptions and guest continuations | Supported with the existing continuation/GC storage restrictions |
| memory32, memory64, multi-memory and bulk operations | Supported within managed allocation capacity |
| Shared memory, atomic accesses, wait/notify | `UnsupportedHostCapability`; never emulated with ordinary memory |
| Native executable pointers, JIT, native stack switching | Not provided |
| Guest WASI, Components and HTTP worlds | Not provided by this module |
| Threads | Not advertised |

`runtime_capabilities()` reports JIT, Component and WASIp1 host availability as
false on wasm. Native capabilities retain their existing values. The separate
Core conformance adapter reports unsupported host mechanisms separately from
passes and failures and exits nonzero for an unsupported file.

## Native source compatibility

The existing `wasmoon/runtime`, `wasmoon/executor`, `wasmoon/logger` and moved
`wasmoon_jit` package paths remain native reexport facades. C and assembly source
ownership moved once; the facades do not compile duplicate definitions.

A MoonBit type reexport preserves type identity and methods, but does not provide
all old package-qualified enum constructor shortcuts. Where needed, change
`@runtime.StackUnderflow` to `@runtime.RuntimeError::StackUnderflow` (similarly for
`GuestContinuationSignal`). Pattern matching with an inferred error type remains
available. New portable code imports the canonical `wasmoon_runtime` paths.
The wasm Store/Linker constructors cannot fail native-state allocation and do not
declare that native-only error effect. Native constructors retain their effect.

## Verification

```sh
moon check modules/wasmoon_runtime/runtime modules/wasmoon_runtime/executor \
  --target wasm --warn-list +73 --deny-warn
moon test modules/wasmoon_runtime/runtime modules/wasmoon_runtime/executor \
  modules/wasmoon_runtime/wast --target wasm --warn-list +73 --deny-warn
python3 scripts/run_portable_core_wast.py
```

The corpus runner builds two actual executables from the same interpreter,
executes every selected WAST file on both targets, checks exit statuses and
assertion counts, and retains per-file source hashes and diagnostics. The
`Wasm interpreter` CI job explicitly selects these runtime packages and the
embedding, so filtering native packages out cannot create a false green.
Platform-native CI and sanitizer acceptance remain separate requirements.

### Strict text validation

The first strict run exposed [ISS-642](../issues/ISS-642.md): 628 existing
malformed-text false accepts across 22 Core files. The old native runner rejected
quoted sources unconditionally, so its earlier green tally did not prove text
validity. Both runners now actually parse the quoted source; a valid quoted
`(module)` is a negative control that must fail `assert_malformed`.

The frontend now checks complete numeric grammar and widths before conversion,
strict UTF-8 names while preserving arbitrary data bytes, annotation lexing,
name uniqueness, import/start rules, type-use ordering/signature consistency,
and matching control labels. Implicit WAST modules reuse the ordinary module
parser. Component text reconstruction preserves original Core string spelling,
so byte escapes cannot be normalized away before Core validation.

The local strict run passes all 258 files and 62,563 assertions on each actual
native and wasm interpreter artifact; the native JIT runner also passes all
62,563 assertions. See [local evidence](evidence/portable-interpreter-2026-10-19/README.md).
These results supersede the initial shortcut-based result. Platform CI, including
Linux leak detection and Windows Clang/MSVC, remains pending submission.
