# Wasmoon Architecture

Wasmoon is a WebAssembly runtime written in MoonBit. It provides an interpreter and native JIT compilation for AArch64 and AMD64, while also developing reusable compiler-infrastructure modules that are not owned by the Wasmoon runtime.

## System Overview

```text
WAT text ───────────────→ wasmoon/wat ──┐
core Wasm binary ───────→ wasmoon/parser ├─→ wasm_core model ─→ validator ─→ instantiation
WAST test script ───────→ wasmoon/wast ──┘                                      │
                                                                                 ├─→ executor interpreter
                                                                                 └─→ Wasm frontend
                                                                                      → MilkIR
                                                                                      → MachV
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

| Module | Responsibility |
| --- | --- |
| `wasm_core` | WebAssembly specification data model shared by parsers, validators, frontends, and runtimes. |
| `milkir` | Target-independent SSA IR, builders, verification, optimization, and CFG utilities. |
| `machv` | Target-neutral semantic machine IR: typed values, CFG, calls, effects, traps, and safepoints. |
| `regalloc` | Machine-IR-independent register-allocation algorithms. |
| `wasm_milkir` | WebAssembly dialect definitions and extension contracts for MilkIR. |
| `milkir_machv` | Verified lowering from core MilkIR into target-neutral MachV. |
| `wasm_machv` | WebAssembly dialect lowering into target-neutral MachV through an embedding environment. |
| `machv_regalloc` | Narrow adapter from generic Target VCode to the reusable register allocator. |
| `x64_target`, `aarch64_target` | Complete AMD64 and AArch64 target pipelines: instruction selection, ABI legalization, allocation policy, frame layout, emission, relocations, and linking. |

Reusable modules must not import `Milky2018/wasmoon`, `Milky2018/wasmoon_jit`, or Wasmoon-native FFI packages. `scripts/audit_module_boundaries.py` enforces that hard dependency direction.

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
| Core `.wasm` binary | `wasmoon/parser` | `wasm_core/types.Module` |
| Core `.wat` text | `wasmoon/wat` | `wasm_core/types.Module` |
| `.wast` script | `wasmoon/wat` plus `wasmoon/wast` runner | Test commands and modules |
| Component binary or text | `wasmoon/component/*` | Component-model structures and runtime inputs |
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
4. Lower verified MilkIR through `milkir_machv` and `wasm_machv` into target-neutral MachV.
5. Lower semantic MachV into verified AArch64 or x64 Target VCode.
6. Expose Target VCode directly through the read-only `regalloc.FunctionView`, run the verified backtracking allocator through `machv_regalloc`, materialize its `AllocationPlan`, and construct a verified target frame.
7. Let the selected target emit machine code, relocations, traps, and safepoint metadata into an unlinked code object.
8. Package compiled functions as an in-memory or serialized v9 artifact with symbolic relocations and an exact compatibility manifest.
9. Let `wasmoon_jit` verify compatibility, resolve runtime symbols, transactionally install code, initialize VMContext state, and enter native code through Wasmoon-owned trampolines.

At O3, MilkIR may unroll only canonical constant-trip natural loops after checked signed/unsigned I32 or I64 trip analysis and complete SSA/effect remapping. Unsupported shapes, dynamic bounds, possible arithmetic wraparound, and transformations beyond the code-growth budget remain unchanged.

The top-level `wasmoon/wasm_frontend` package is the product API boundary. Product callers do not import `wasmoon/wasm_frontend/ir` directly.

## IR and ABI Boundaries

MilkIR uses SSA values and block parameters rather than WebAssembly operand-stack state. Its core opcode contract consists of five semantic families: scalar, memory, call, vector, and typed extension operations. WebAssembly-specific operations are represented through the `wasm_milkir` dialect or lowered into ordinary MilkIR operations by the frontend. Source-only fields such as WebAssembly SIMD memory indices, alignment hints, and immediate offsets are consumed before core IR construction.

Semantic MachV represents function-owned typed values, blocks, explicit edge arguments, calls, effects, traps, safepoints, and target-neutral operations. Target-specific operations exist only inside `aarch64_target` or `x64_target` VCode, so an instruction from one architecture cannot be represented in the other target function. Each target module owns calling-convention legalization and physical-register policy, while Wasmoon-specific VMContext meanings remain owned by `wasmoon_jit`.

Register allocation does not own or copy a second machine-IR graph. `machv_regalloc` adapts the selected target VCode to the reusable allocator's read-only `FunctionView`; both production targets explicitly select the backtracking strategy. The aggregate target pipeline verifies selected VCode before allocation and independently verifies the materialized VCode allocation before frame planning. `SinglePass` remains an explicit library option and is not a production fallback.

Each target emitter produces machine code and symbolic metadata. Resolving Wasmoon runtime helpers, allocating executable memory, installing signal/trap integration, and constructing VMContext state occur after emission in `wasmoon_jit`. See [JIT ABI](jit-abi.md) for the embedding contract and the target modules for executable policy definitions.

## Capability Coverage and Readiness

The repository includes broad implementation and test coverage for core WebAssembly, WASI Preview 1, SIMD, GC/reference proposals, exceptions, memory/table extensions, and an evolving subset of the component model. Presence in the source tree or test suite does not mean every specification corner, embedding configuration, operating system, or adversarial input has been audited.

Wasmoon is primarily developed with AI assistance and has not received the security review expected of a production WebAssembly sandbox. The interpreter, JIT native glue, process-level trap handling, WASI host access, component runtime, and proposal implementations should be treated as experimental unless independently audited for the intended deployment. Do not use the project as a security boundary or in production merely because a feature is listed as supported.

Current capability and command summaries live in the root README. Component-model limitations are tracked in [component/unsupported-matrix.md](component/unsupported-matrix.md), and development validation commands are documented in [development.md](development.md).

The native JIT uses the same verified register-allocation seam on both targets.
Target correctness, ABI behavior, metadata, and artifact validity are enforced
by CI. Historical backends are not retained or rebuilt as performance or
code-size baselines.
