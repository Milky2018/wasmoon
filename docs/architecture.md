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
| `machv` | Virtual-register machine IR and generic ABI/ISA data structures. |
| `regalloc` | Machine-IR-independent register-allocation algorithms. |
| `wasm_milkir` | WebAssembly dialect definitions and extension contracts for MilkIR. |
| `milkir_machv` | Generic MilkIR-to-MachV lowering support. |
| `wasm_isa_lower` | WebAssembly-specific lowering from MilkIR into target-aware MachV. |
| `machv_regalloc` | Adapter between MachV and the reusable register allocator. |
| `machv_emit` | Machine-code bytes plus symbolic relocation, stack-map, and debug metadata. |
| `x64_target`, `aarch64_target` | AMD64 and AArch64 target policies and instruction selection. |

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
4. Lower MilkIR through `wasm_isa_lower` and target policy into MachV.
5. Allocate physical registers through `machv_regalloc` and `regalloc`.
6. Emit AArch64 or AMD64 machine code and symbolic metadata through `machv_emit`.
7. Package compiled functions as an in-memory or serialized CWASM artifact.
8. Let `wasmoon_jit` resolve runtime symbols, install code, initialize VMContext state, and enter native code through Wasmoon-owned trampolines.

At O3, MilkIR may unroll only canonical constant-trip natural loops after checked signed/unsigned I32 or I64 trip analysis and complete SSA/effect remapping. Unsupported shapes, dynamic bounds, possible arithmetic wraparound, and transformations beyond the code-growth budget remain unchanged.

The top-level `wasmoon/wasm_frontend` package is the product API boundary. Product callers do not import `wasmoon/wasm_frontend/ir` directly.

## IR and ABI Boundaries

MilkIR uses SSA values and block parameters rather than WebAssembly operand-stack state. Its core opcode contract consists of five semantic families: scalar, memory, call, vector, and typed extension operations. WebAssembly-specific operations are represented through the `wasm_milkir` dialect or lowered into ordinary MilkIR operations by the frontend. Source-only fields such as WebAssembly SIMD memory indices, alignment hints, and immediate offsets are consumed before core IR construction.

MachV represents virtual registers, physical-register constraints, calls, clobbers, blocks, and target instructions. Target modules and the embedding ABI supply calling-convention policy; Wasmoon-specific VMContext slot meanings and pinned-register roles remain owned by `wasmoon_jit`.

The emitter produces machine code and symbolic metadata. Resolving Wasmoon runtime helpers, allocating executable memory, installing signal/trap integration, and constructing VMContext state occur after emission in `wasmoon_jit`. See [JIT ABI](jit-abi.md) for the AArch64 contract and the target modules for executable policy definitions.

## Capability Coverage and Readiness

The repository includes broad implementation and test coverage for core WebAssembly, WASI Preview 1, SIMD, GC/reference proposals, exceptions, memory/table extensions, and an evolving subset of the component model. Presence in the source tree or test suite does not mean every specification corner, embedding configuration, operating system, or adversarial input has been audited.

Wasmoon is primarily developed with AI assistance and has not received the security review expected of a production WebAssembly sandbox. The interpreter, JIT native glue, process-level trap handling, WASI host access, component runtime, and proposal implementations should be treated as experimental unless independently audited for the intended deployment. Do not use the project as a security boundary or in production merely because a feature is listed as supported.

Current capability and command summaries live in the root README. Component-model limitations are tracked in [component/unsupported-matrix.md](component/unsupported-matrix.md), and development validation commands are documented in [development.md](development.md).
