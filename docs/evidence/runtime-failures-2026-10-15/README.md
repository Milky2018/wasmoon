# Recoverable runtime failures (ISS-625)

This review covers error propagation, failure atomicity, native callback
unwinding, and reuse after a rejected operation. It is a manual source review
with deterministic fault regressions, not a claim that every allocation is
recoverable or that the runtime is a security sandbox.

Baseline: `a694f4aabe26ce8fd9d72b15f2bbfe2488b48ee6`.
Implementation branch: `milky/propagate-runtime-failures` (uncommitted during
validation). Host: macOS ARM64, stable MoonBit `0.1.20261012 (748b63c)`.

## Independently reproduced failures

1. The validator accepts `(module (memory i64 281474976710656))`. Its minimum
   cannot fit the runtime's memory representation. The old simple instantiation
   path used `try!` and terminated with SIGABRT instead of returning the existing
   `MemoryMinimumExceedsLimits` error. The regression catches that error and
   instantiates and executes a second module in the same process.
2. A MoonBit host callback called `throw_exception_values` under a guest
   `try_table`. The guest received `37`, but the callback's `defer` did not run.
   The managed FFI called the guest's `longjmp` path directly, skipping managed
   cleanup and RC decrements. The new regression explicitly observes cleanup,
   rather than inferring it from a correct guest result.
3. A builder with 1025 DWARF functions printed a capacity warning, discarded
   the extra function and still returned successful registration. The regression
   now rejects the incomplete object and preserves the previous active builder.
4. Source review found native memory/table binding functions silently returning
   on allocation failure. The MoonBit table list was replaced before that
   native operation, allowing two conflicting binding views. Both setters now
   return checked statuses; replacements commit only after preparation succeeds.

The captured failing observations are [capacity abort](capacity-before.log),
[skipped callback cleanup](callback-cleanup-before.log), and
[lost Component resource category](component-category-before.log), and
[truncated DWARF registration](dwarf-capacity-before.log).

The checked-in regressions live in
[shared runtime failure tests](../../../modules/wasmoon/sanitizer_testsuite/runtime_failures_test.mbt),
[native ownership and failure tests](../../../modules/wasmoon_jit/native_handles_test.mbt),
and [native failure probes](../../../modules/wasmoon_jit/native_test_support/failure_test_support.c).
The shared tests are copied into the sanitizer closure by the existing runner.

## Error-path inventory

| Boundary | Reviewed behavior and disposition |
| --- | --- |
| Core binary/text parsing and validation | Existing parse/validation errors remain structured. Validator structured-control dispatch uses a work stack; its private instruction validator's structured-control fatal branch is not a public parsing error path. Existing malformed-input, validation-depth and corpus tests cover the public boundary. |
| Simple Core instantiation | `instantiate_module` now raises `RuntimeError` and closes its newly owned Store on failure. Memory/table construction, const evaluation and Store publication propagate errors. `instantiate_module_with_init` closes that Store if element/data initialization or the start function fails. |
| Linked Core instantiation | Existing `InstantiationTransaction` remains explicit. Tests repeatedly fail after partial allocation, roll back functions, memories and instance state, then run a valid module in the same Store, with both heap representations. Imported memory/table mutations and escaped guest references during a trapping start function are observable Wasm effects; unconditional rollback would be incorrect. |
| Memory construction/access/growth | Invalid host page sizes, reversed limits and shared memory without a maximum are `InvalidMemoryType`. Unrepresentable valid minima retain `MemoryMinimumExceedsLimits`; native allocation denial is `OutOfMemory`. Missing Store memory raises `UndefinedElement`; it no longer allocates a dummy memory. Failed growth returns the Wasm `-1` result and preserves bytes and length, followed by a successful growth. Closed aliases retain their existing checked behavior. |
| Table construction/growth | Reversed limits are `InvalidTableType`; unrepresentable minima and native allocation denial retain typed table errors. Publication happens after allocation. Failed growth preserves contents and permits a later valid growth. |
| Store/GC heap preparation | Exception/continuation arena and native heap constructors check allocation immediately. Store and Linker constructors propagate resource denial. `enable_c_heap` creates a replacement before committing it and rejects switching a Store containing live interpreter objects with `HeapRepresentationInUse`. The CLI selects its heap before preloads can allocate objects. |
| GC allocation and collection | Existing typed GC allocation errors remain. Native execution-state, root-frame, scratch-root and root-scope allocation failures return checked status/OOM. Failed entry root copying restores prior execution state and releases retained controls. Live exception seed marking no longer needs a temporary allocation or a `longjmp`. Failure probes verify an existing object and its roots survive denial and the next allocation succeeds. |
| Native binding replacement | Memory and table setters distinguish allocation failure from invalid/closed context or layout capacity. Closed/uninitialized module preparation rejects the operation rather than reporting no-op success. The Store-to-JIT adapter propagates typed Core errors rather than reducing them to `None`. Table snapshots retain replacements before releasing old bindings. MoonBit commits its corresponding list after native success. Tests check preserved bindings and a later successful replacement. |
| JIT metadata | Invalid GC type stride, mismatched safepoint arrays and external-object payload bounds raise `GCMetadataError`/`ArtifactLoadError`; checks precede large payload allocation. Existing immutable ownership and parked-frame tests cover replacement and teardown. |
| Executable code and artifact installation | The installer retains its existing typed errors and rollback tests for unresolved symbols/relocations. A denied executable mapping now has deterministic coverage through the same allocation hook, followed by successful installation and release. Code-block tracking and page rounding check overflow before arithmetic. |
| DWARF registration | Buffer growth retains the old allocation on failure, records a sticky failure, and stops subsequent writes/padding. ELF, Mach-O and COFF builders propagate failure and release partial buffers. Exceeding the fixed function capacity records a preparation failure instead of registering a silently truncated object. Registration publishes only a complete object and entry. Fault sweeps reject successive preparation allocations, preserve the previously active builder, and successfully retry the same new builder. |
| Guest traps and native EH | Native-only guest helper paths keep their trap activation/handler `longjmp` contract. EH handler and spill allocation denial map to trap code 9, rather than internal-error code 99 or a successful-looking empty spill. Spill replacement preserves the previous snapshot until copying succeeds. |
| Managed host exception delivery | Managed APIs stage payloads and return through MoonBit. C delivers the pending exception only after the callback returns and dynamic hostcall slots are restored. Calling the managed API without its active callback returns `InvalidBinding`. Payload denial returns `ExceptionPayloadAllocationFailed`; the dispatcher maps it to OOM. Imported exceptions use Store tag identities, including tags absent from the caller module. |
| Host callbacks and error categories | A temporary RC reference keeps the executing callback alive if it clears its registration. Resume reloads the current callback rather than calling a stale function with replaced data. Tests distinguish a host `OutOfMemory` error from guest `unreachable`, observe `defer` before host exit, and invoke successfully afterward. Existing cancellation/suspension/reentry tests verify their separate outcomes. |
| Native startup/platform preparation | Trap handler installation reports failure, rolls back partial POSIX registration, and publishes success only after all handlers succeed. Linux stack queries and alternate-stack setup are checked. Windows thread-to-fiber conversion and fiber bootstrap preparation return a resource failure without running the entry; tests cover retryable Ready state, failed-start Cancelled state and a subsequent successful fiber. Windows execution requires CI acceptance. |
| WASIp1 and command adapters | WASI callbacks map missing/closed guest memory to `FAULT`. CLI construction, WASI/spectest/preload registration, table preparation and debug registration report failures instead of using `try!`. The CLI closes its owned Linker on every return. Guest errno, host exit and cancellation conventions remain distinct. |
| Component Model | Engine Store preparation can raise a Core runtime error. Failed Component linker construction closes the partially prepared engine and Core linker. Public `ResourceExhausted` preserves resource errors through construction/instantiation; `HostExit` and `Cancelled` retain their existing identities. Fault injection exercises partial constructors and native compilation/installation, then instantiates and calls another component in the same runtime. Native preparation releases temporary function registrations and executable state on failure. |
| Close and cancellation | Existing owner close/finalizer paths remain idempotent and preserve retained aliases. Cancellation callbacks return before native stack suspension or trap delivery. Shared lifecycle, parked continuation, async task and external-event-loop regressions run in the native/sanitizer gates. |

## Retained fatal operations and their preconditions

These are deliberately classified by reachability rather than symbol counts.

- `runtime/instance.mbt` and executor continuation type extraction require a
  previously validated, unchanged Core model. Public mutable model hardening is
  ISS-626; this repair does not pretend those raw types are opaque.
- The private SIMD dispatcher is entered only through `exec_instr`'s explicit
  SIMD variant list. The validator's scalar instruction function is called only
  after its work stack removes structured control. Their default fatal branches
  indicate broken internal dispatch, not an unsupported valid guest operation.
- Callable registry `replace` currently constructs MoonBit arrays and always
  returns `true`. Its legacy false-result guards are not a native fallible
  allocation boundary. MoonBit allocator exhaustion remains outside this repair.
- Native activation/root-scope LIFO assertions, destroying a table with live
  native bindings, destroying a heap with parked registrations, and unexpected
  fiber bootstrap/return states guard ownership and control-flow invariants.
  The ownership and reentry regressions exercise their valid transitions.
- `atomic.c` is reached through checked memory operations with fixed widths
  `{1,2,4,8}` and RMW operations `{0..5}`; malformed external calls to private C
  symbols are outside that interface. The native monotonic clock helpers still
  require the supported OS clock facility to work. Their fatal OS-failure guards
  are not converted to fabricated times or successful waits. Recovery from a
  broken/denied platform clock remains a limit of this review.
- Windows `ConvertFiberToThread` reversal and `_resetstkoflw` guards still fail
  fatally if the OS cannot restore the current thread's established execution
  environment. Startup allocation/setup rejection is handled separately above.
- Opt-in native heap verification aborts on heap corruption. Generated WASI
  resource-contract lookups and argparse shape checks guard generated/static
  declarations, not guest-supplied resource names or unchecked CLI input.
- Fatal assertions and `try!` in test fixtures are not production error paths.

## Failure injection and compatibility

The private per-thread test hook rejects exactly one selected native allocation
or OS resource acquisition. It is disabled by default, resets after the rejected
request, and does not add an environment-controlled production failure policy.
It covers the native allocation seams under test; it does not intercept
MoonBit's allocator. Tests reset it when sweeping beyond the number of requests.

Several constructors now have a throwing signature: `Memory`, `Store`, `Linker`,
`CHeap`, native execution arenas, and Component runtime/linker preparation.
Native binding, segment/GC frame setup, managed exception staging and DWARF
registration also expose failures. Callers must propagate or handle these
errors. Returning an invalid owner or silently retaining old state would keep
source signatures stable at the cost of an incorrect success contract.
Generated `.mbti` files record the changes.

MoonBit allocator termination, OS process killing, aggregate Store budgets and
compiler complexity limits are not made catchable here (ISS-627). TLS error
classification remains ISS-568. These are not reasons to flatten the recoverable
errors covered above into guest traps or process aborts.

## Validation

Validation results are recorded below after running the final source tree.
Linux LSan and Windows Clang/MSVC must be validated on those platforms; a macOS
ASan run is not evidence that they passed.

An intermediate incremental build mixed old/new private struct layouts. ASan
reported a 1096-byte initialization into a 1088-byte stack allocation. Clean
native and sanitizer rebuilds removed the mismatch; final checks did not reuse
those objects. [ISS-634](../../../issues/ISS-634.md) tracks dependency/cache
invalidation separately; [the failing ASan trace](abi-cache-before.log) is
preserved. Do not treat that intermediate crash as a passing sanitizer run.

Final local results are captured in [results.json](results.json), including the
uncommitted source digest and executable/sanitizer hashes:

| Gate | Result |
| --- | --- |
| `moon info`; `moon fmt` | Passed; generated interfaces refreshed |
| `moon check --target native --warn-list +73 --deny-warn` | Passed |
| `moon test --target native` | 2664/2664 |
| `python3 scripts/check_native_c.py` | 41 C stubs; warnings denied |
| `python3 scripts/audit_module_boundaries.py` | Passed |
| `python3 scripts/run_sanitizers.py` | 124/124; external event-loop fixture passed; both positive controls detected ASan violations |
| `./install.sh` | Passed; rebuilt release binaries |
| Core WAST (`run_all_wast.py --rec --dump-failures`) | Both engines: 258/258 files, 62,563 assertions each |
| Component stable-0.2 | Both engines: 23/23 files, 845 commands each, no skips |
| Component async-0.3 | Both engines: 24/24 files, 153 commands each, no skips |
| Component future-gated | Both engines: 12/12 files, 387 commands each, no skips |
| Wasmtime misc (`--include-high-memory --timeout 120`) | 692 pass, 72 script-only, no failures/timeouts/unsupported/deferred cases |
| Wasmtime WASIp1 (`--profile capabilities`) | 116 pass, 2 policy exclusions (`p1_cli_hostcall_fuel`, one per engine); no failures |
| Upstream WASI 0.3 (`--http-contract-tests --timeout 120`) | 110 pass; pinned `609c446139956ff30239f87cb18af1dc6128bed2`; both engines |
| HTTP end-to-end (`test_wasi_http.py`) | Both engines; streaming, disconnects, traps, capability denial, concurrent command execution |
| JIT cache lifecycle (`run_jit_cache.py`) | Cold, warm, corrupt, write-failed and unavailable cases passed |
| WASIp1 allocation (`run_wasi_allocation.py`) | Both engines; dense success and sparse `NOTSUP` without unintended allocation |
| GC fault/stress (`find_gc_bugs.py --dir spec/gc --timeout 30 --max-files 64 --fault-alloc-every 7`) | 17/17 in normal, JIT, stress and small-heap lanes; no regressions, trap mismatches or crashes; 3 expected non-pass fault lanes |

The sanitizer uses the system allocator and instruments native stubs and the
MoonBit test closure. It excludes MoonBit runtime object code and emitted JIT
machine code. macOS ASan/UBSan results do not establish Linux leak freedom.
Linux LSan and Windows Clang/MSVC acceptance remain pending. No commit, push or
PR was created during this implementation request.
