# Wasmoon Architecture

Wasmoon is a WebAssembly runtime written in MoonBit. It provides an interpreter and native JIT compilation for AArch64 and AMD64, while also developing reusable compiler-infrastructure modules that are not owned by the Wasmoon runtime.

## System Overview

```text
WAT text ───────────────→ wasmoon/wat ──┐
core Wasm binary ───────→ wasm_core/parser ├─→ wasm_core model ─→ validator ─→ instantiation
WAST test script ───────→ wasmoon/wast ──┘                                      │
                                                                                 ├─→ executor interpreter
                                                                                 └─→ Wasm frontend
                                                                                      → MilkIR
                                                                                      → direct target lowering
                                                                                      → target VCode
                                                                                      → target allocation/emission
                                                                                      → verified code object
                                                                                      → v9 artifact
                                                                                      → wasmoon_jit installer
```

The `wasmoon run` command validates both the main module and preloaded core modules before instantiation. Library callers that assemble parsing, validation, and execution themselves remain responsible for preserving the same boundary.

## Workspace and Ownership

The repository is a `moon.work` workspace containing several independently versioned MoonBit modules.

### Reusable specification and compiler infrastructure

| Module or package | Responsibility |
| --- | --- |
| `wasm_core` | WebAssembly specification data model shared by parsers, validators, frontends, and runtimes. |
| `milkir` | Target-independent SSA IR, builders, verification, optimization, and CFG utilities. |
| `vcode/native_types` | Target-independent native ABI, type, symbol, trap, safepoint, and metadata vocabulary. |
| `vcode/native_lowering` | Streaming target-lowering protocol; carries one operation at a time and retains no function graph. |
| `regalloc` | Machine-IR-independent register-allocation algorithms. |
| `wasm_milkir` | WebAssembly dialect definitions and extension contracts for MilkIR. |
| `milkir/native` | Verified direct streaming from core MilkIR into a native target sink. |
| `wasm_milkir/native` | WebAssembly dialect validation and streaming native lowering through an embedding environment. |
| `vcode` | Generic dense Target VCode, allocation side tables, validation, and parallel-move planning. |
| `vcode/code_object` | Verified unlinked native code, relocations, traps, safepoints, roots, and unwind metadata. |
| `vcode_regalloc` | Narrow adapter from generic Target VCode to the reusable register allocator. |
| `x64_target`, `aarch64_target` | Complete AMD64 and AArch64 target pipelines: instruction selection, ABI legalization, allocation policy, frame layout, emission, relocations, and linking. |

Reusable modules and packages must not import `Milky2018/wasmoon`, `Milky2018/wasmoon_jit`, or Wasmoon-native FFI packages. `scripts/audit_module_boundaries.py` enforces that hard dependency direction.

### Wasmoon-owned product modules

| Module or package | Responsibility |
| --- | --- |
| `wasmoon` | Product assembly, CLI, parsing, validation, runtime objects, interpreter, WASI Preview 1, component-model work, and test runners. |
| `wasmoon/wasm_frontend` | Canonical product-facing Wasm-to-MilkIR frontend API. Its `ir` subpackage is an implementation detail; embedding configuration lives in the dependency-neutral `embedding` subpackage. |
| `wasmoon_jit` | Wasmoon VMContext layout, native runtime helpers, trampolines, runtime symbol resolution, and transactional executable-code installation. |
| `wasmoon_jit/artifact` | Bounded v9 persisted-artifact format with exact compatibility manifests and symbolic unlinked code objects. |

`wasmoon_jit` intentionally belongs to the Wasmoon product side even though it consumes reusable compiler infrastructure.

## Parsing and Validation

| Input | Entry package | Result |
| --- | --- | --- |
| Core `.wasm` binary | `wasm_core/parser` | `wasm_core/types.Module` |
| Core `.wat` text | `wasmoon/wat` | `wasm_core/types.Module` |
| `.wast` script | `wasmoon/wat` plus `wasmoon/wast` runner | Test commands and modules |
| Component binary or text | `wasmoon/component` | Validated component instances, typed exports, and WIT-shaped values |
| Persisted JIT artifact | `wasmoon_jit/artifact` | Verified v9 ordinary-data artifact |

Core modules pass through `wasmoon/validator` before the CLI instantiates or compiles them. Component validation is implemented separately under `wasmoon/validator/component_model`.

## Execution Paths

### Interpreter

1. Parse WAT or core Wasm into the shared `wasm_core` model.
2. Validate the decoded module.
3. Instantiate imports, memories, tables, globals, elements, data segments, and the start function.
4. Execute through `wasmoon/executor` using runtime state from `wasmoon/runtime`.

### Native JIT

1. Parse and validate the core module.
2. Build a canonical `wasmoon/wasm_frontend` translation context.
3. Translate each selected function into MilkIR and run the requested optimization level.
4. Stream verified core and WebAssembly-dialect MilkIR operations directly into an AArch64 or x64 lowering session, which constructs verified Target VCode.
5. Expose Target VCode directly through the read-only `regalloc.FunctionView`, run the verified backtracking allocator through `vcode_regalloc`, materialize its `AllocationPlan`, and construct a verified target frame.
6. Let the selected target emit machine code, relocations, traps, and safepoint metadata into an unlinked code object.
7. Package compiled functions as an in-memory or serialized artifact with symbolic relocations and an exact compatibility manifest.
8. Let `wasmoon_jit` verify compatibility, resolve runtime symbols, transactionally install code, initialize VMContext state, and enter native code through Wasmoon-owned trampolines.

At O3, MilkIR may unroll only canonical constant-trip natural loops after checked signed/unsigned I32 or I64 trip analysis and complete SSA/effect remapping. Unsupported shapes, dynamic bounds, possible arithmetic wraparound, and transformations beyond the code-growth budget remain unchanged.

The top-level `wasmoon/wasm_frontend` package is the product API boundary. Product callers do not import `wasmoon/wasm_frontend/ir` directly.

### Component Core Execution

The component linker owns a `CoreExecutionEngine` seam rather than calling the
core interpreter directly. After a core module is instantiated, the engine
registers the shared module instance and receives a typed request for each
entry:

- `RunToCompletion` enters native JIT code and returns ordinary core results.
- `CallbackStep` enters native code for one Component Async callback step and
  returns normally to the scheduler.
- `Stackful` enters native code on a guarded fiber stack. A suspending canonical
  hostcall parks the activation and returns an opaque continuation.

Native resumption restores the original machine stack, hostcall and trap
activation state, and precise GC roots, then continues after the suspended
hostcall without replay. Explicit interpreter mode provides the equivalent
structured continuation. `PreferNative` is strict; an unavailable native route
is a structured error rather than an implicit fallback. Interpreter-owned
imports and re-exports request `InterpreterOnly` explicitly.

The default `component --run` and `component-test` commands enable the JIT
engine. `--no-jit` selects the interpreter engine for differential testing.

The stable library surface is `Milky2018/wasmoon/component`. It owns opaque
engine, runtime, instance, function, and call handles plus typed values and
structured errors; applications do not depend on `component/runtime_impl`.
Default construction uses the strict native engine, while
`interpreter_component_engine()` selects the continuation-aware interpreter
explicitly. The CLI uses this same facade and engine seam.
`Milky2018/wasmoon/wit` can bind a resolved world eagerly against a stable
component instance, rejecting missing or incompatible exports before the first
call.

Component async execution uses one cooperative host event loop. MoonBit
processes and component tasks are logical scheduling units, not operating-system
threads. `component/runtime_impl` owns guest-visible tasks, waitables, and
continuations. The native adapter translates kqueue on macOS and epoll on Linux
into opaque `Pending`, `Ready`, or `Cancelled` host registrations. Host futures
observe those registrations through non-blocking `poll` and idempotent
`cancel` operations; the component scheduler resumes the stored continuation
when a host event becomes ready.

A Store and its continuations remain on their creation thread. Multiple parked
continuations may exist, but only one component entry chain is active at a
time. Cancellation is cooperative at scheduler and hostcall boundaries; it
releases the host registration, native stack, and parked GC roots without
arbitrary-instruction preemption.

Native WASI 0.3 execution is supported on macOS AArch64 and Linux AMD64.
Windows, multi-threaded Store access, cross-thread continuation migration,
continuation serialization, and arbitrary-instruction preemption are explicit
non-goals. Embeddings must finish or cancel outstanding continuations before
the terminal, idempotent `ComponentLinker::close` call.

## IR and ABI Boundaries

MilkIR uses SSA values and block parameters rather than WebAssembly operand-stack state. Its core opcode contract consists of five semantic families: scalar, memory, call, vector, and typed extension operations. WebAssembly-specific operations are represented through the `wasm_milkir` dialect or lowered into ordinary MilkIR operations by the frontend. Source-only fields such as WebAssembly SIMD memory indices, alignment hints, and immediate offsets are consumed before core IR construction.

`vcode/native_lowering` passes opaque transient value and block handles plus one operation at a time to the selected target. It deliberately does not own function CFG, SSA, instruction, or verification storage; MilkIR remains the sole target-independent program representation. Target-specific operations exist only inside `aarch64_target` or `x64_target` VCode, so an instruction from one architecture cannot be represented in the other target function. Each target module owns calling-convention legalization and physical-register policy, while Wasmoon-specific VMContext meanings remain owned by `wasmoon_jit`.

Register allocation does not own or copy a second machine-IR graph. `vcode_regalloc` adapts the selected target VCode to the reusable allocator's read-only `FunctionView`; both production targets use the same bundle-aware allocator. The aggregate target pipeline verifies selected VCode before allocation and independently verifies the materialized VCode allocation before frame planning. There is no lower-quality fallback allocator.

Target-neutral parallel assignments are linearized in `vcode` with one
dedicated transfer scratch per register bank. A shared legalization pass emits
explicit emergency save and restore steps when a stack-to-stack transfer would
otherwise clobber a live cycle value. Each target owns the optional physical
16-byte frame area and verifies its presence against the resolved move groups;
the area is raw codegen storage rather than an allocated stack slot or GC root.

Each target emitter produces machine code and symbolic metadata. Resolving Wasmoon runtime helpers, allocating executable memory, installing signal/trap integration, and constructing VMContext state occur after emission in `wasmoon_jit`. See [JIT ABI](jit-abi.md) for the embedding contract and the target modules for executable policy definitions.

## Capability Coverage and Readiness

The repository includes broad implementation and test coverage for core WebAssembly, WASI Preview 1, SIMD, GC/reference proposals, exceptions, memory/table extensions, and an evolving subset of the component model. Presence in the source tree or test suite does not mean every specification corner, embedding configuration, operating system, or adversarial input has been audited.

Wasmoon is primarily developed with AI assistance and has not received the security review expected of a production WebAssembly sandbox. The interpreter, JIT native glue, process-level trap handling, WASI host access, component runtime, and proposal implementations should be treated as experimental unless independently audited for the intended deployment. Do not use the project as a security boundary or in production merely because a feature is listed as supported.

Current capability and command summaries live in the root README. Component-model limitations are tracked in [component/unsupported-matrix.md](component/unsupported-matrix.md), and development validation commands are documented in [development.md](development.md).

The native JIT uses the same verified register-allocation seam on both targets.
Target correctness, ABI behavior, metadata, and artifact validity are enforced
by CI. Historical backends are not retained or rebuilt as performance or
code-size baselines.
