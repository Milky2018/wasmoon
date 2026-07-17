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
                                                                                      → register allocation
                                                                                      → machine-code emission
                                                                                      → wasmoon_jit
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
| `machv_regalloc` | Physical-register allocation for the current private downstream backend. |
| `machv_emit` | Machine-code bytes plus symbolic relocation, stack-map, and debug metadata for that backend. |
| `x64_target`, `aarch64_target` | AMD64 and AArch64 ABI and register policy. |

Reusable modules must not import `Milky2018/wasmoon`, `Milky2018/wasmoon_jit`, or Wasmoon-native FFI packages. `scripts/audit_module_boundaries.py` enforces that hard dependency direction.

### Wasmoon-owned product modules

| Module or package | Responsibility |
| --- | --- |
| `wasmoon` | Product assembly, CLI, parsing, validation, runtime objects, interpreter, WASI Preview 1, component-model work, and test runners. |
| `wasmoon/wasm_frontend` | Canonical product-facing Wasm-to-MilkIR frontend API. Its `ir` subpackage is an implementation detail; embedding configuration lives in the dependency-neutral `embedding` subpackage. |
| `wasmoon_jit` | Wasmoon VMContext layout, native runtime helpers, trampolines, executable-memory integration, runtime symbol resolution, and CWASM artifacts. |
| `wasmoon_jit/cwasm` | Serialized Wasmoon precompiled native-code format. CWASM is not the parser for ordinary core `.wasm` binaries. |

`wasmoon_jit` intentionally belongs to the Wasmoon product side even though it consumes reusable compiler infrastructure.

## Parsing and Validation

| Input | Entry package | Result |
| --- | --- | --- |
| Core `.wasm` binary | `wasmoon/parser` | `wasm_core/types.Module` |
| Core `.wat` text | `wasmoon/wat` | `wasm_core/types.Module` |
| `.wast` script | `wasmoon/wat` plus `wasmoon/wast` runner | Test commands and modules |
| Component binary or text | `wasmoon/component/*` | Component-model structures and runtime inputs |
| CWASM artifact | `wasmoon_jit/cwasm` | Wasmoon precompiled native module |

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
5. Let the product-private transition layer legalize semantic MachV for the current AArch64 or AMD64 backend.
6. Allocate physical registers through `machv_regalloc` and `regalloc`.
7. Emit machine code and symbolic metadata through `machv_emit`.
8. Package compiled functions as an in-memory or serialized CWASM artifact.
9. Let `wasmoon_jit` resolve runtime symbols, install code, initialize VMContext state, and enter native code through Wasmoon-owned trampolines.

At O3, MilkIR may unroll only canonical constant-trip natural loops after checked signed/unsigned I32 or I64 trip analysis and complete SSA/effect remapping. Unsupported shapes, dynamic bounds, possible arithmetic wraparound, and transformations beyond the code-growth budget remain unchanged.

The top-level `wasmoon/wasm_frontend` package is the product API boundary. Product callers do not import `wasmoon/wasm_frontend/ir` directly.

## IR and ABI Boundaries

MilkIR uses SSA values and block parameters rather than WebAssembly operand-stack state. Its core opcode contract consists of five semantic families: scalar, memory, call, vector, and typed extension operations. WebAssembly-specific operations are represented through the `wasm_milkir` dialect or lowered into ordinary MilkIR operations by the frontend. Source-only fields such as WebAssembly SIMD memory indices, alignment hints, and immediate offsets are consumed before core IR construction.

Semantic MachV represents function-owned typed values, blocks, explicit edge arguments, calls, effects, traps, safepoints, and target-neutral operations. The existing union backend remains an internal downstream implementation detail while target-specific VCode is introduced; it is not a supported MilkIR lowering API. Target modules and the embedding ABI supply calling-convention policy, while Wasmoon-specific VMContext meanings and pinned-register roles remain owned by `wasmoon_jit`.

The emitter produces machine code and symbolic metadata. Resolving Wasmoon runtime helpers, allocating executable memory, installing signal/trap integration, and constructing VMContext state occur after emission in `wasmoon_jit`. See [JIT ABI](jit-abi.md) for the AArch64 contract and the target modules for executable policy definitions.

## Capability Coverage and Readiness

The repository includes broad implementation and test coverage for core WebAssembly, WASI Preview 1, SIMD, GC/reference proposals, exceptions, memory/table extensions, and an evolving subset of the component model. Presence in the source tree or test suite does not mean every specification corner, embedding configuration, operating system, or adversarial input has been audited.

Wasmoon is primarily developed with AI assistance and has not received the security review expected of a production WebAssembly sandbox. The interpreter, JIT native glue, process-level trap handling, WASI host access, component runtime, and proposal implementations should be treated as experimental unless independently audited for the intended deployment. Do not use the project as a security boundary or in production merely because a feature is listed as supported.

Current capability and command summaries live in the root README. Component-model limitations are tracked in [component/unsupported-matrix.md](component/unsupported-matrix.md), and development validation commands are documented in [development.md](development.md).
