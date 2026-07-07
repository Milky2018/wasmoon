# Wasmoon Compiler Infrastructure

This context defines the language used while splitting Wasmoon internals into reusable compiler infrastructure.

## Language

**MilkIR**:
A reusable compiler intermediate representation that is not semantically owned by WebAssembly.
_Avoid_: Generic IR, Wasm IR, wasmoon IR, runtime IR

**MilkIR Core**:
The first supported subset of **MilkIR** needed for WebAssembly lowering, basic optimization, and lowering to **MachV**.
_Avoid_: full Cranelift parity

**Completeness TODO**:
A code comment that marks an intentionally incomplete compiler-infrastructure feature, semantic case, or Cranelift-like capability.
_Avoid_: silent limitation

**Wasm Frontend**:
The part of Wasmoon that lowers WebAssembly modules into **MilkIR**.
_Avoid_: IR translator, parser backend

**Wasm Core**:
The reusable WebAssembly specification model used by parsers, validators, and frontends.
_Avoid_: runtime store, compiler backend, wasmoon runtime

**Embedding Environment**:
The runtime-provided interface that the **Wasm Frontend** uses to lower WebAssembly-specific state and operations into **MilkIR**.
_Avoid_: VMContext when referring to the generic boundary

**Runtime Lowering**:
The translation of runtime-specific operations into ordinary **MilkIR** constructs such as calls, globals, loads, stores, traps, and hidden parameters.
_Avoid_: custom core opcode, Wasm opcode

**Frontend Type System**:
The source-language type model that must be checked and lowered before values enter **MilkIR**.
_Avoid_: IR type system when referring to WebAssembly heap types

**MachV**:
A reusable low-level virtual-register representation used after instruction selection and before machine-code emission.
_Avoid_: VCode, Machine IR

**MilkIR-MachV Lowering**:
The target-specific layer that lowers **MilkIR** into **MachV** and owns instruction selection, calling conventions, and target constraints.
_Avoid_: backend, isa_backend, backend_common before duplication exists, MilkIR, MachV core, wasmoon JIT

**ABI Policy**:
The target and embedding-specific rules for argument registers, return registers, callee-saved registers, caller-saved registers, stack layout, and call clobbers.
_Avoid_: MachV core policy

**Register Allocation**:
The target-independent allocation algorithm that assigns **MachV** virtual registers or spills through an abstract program model.
_Avoid_: regalloc_core, VCode regalloc, machine regalloc

**MachV Register Allocation Adapter**:
The adapter that projects **MachV** functions into the **Register Allocation** model and applies allocation decisions back to **MachV**.
_Avoid_: regalloc

**Wasmoon Runtime**:
The WebAssembly execution system that owns Wasm validation, instantiation, host integration, and runtime semantics.
_Avoid_: compiler infrastructure, wasmoon_runtime as an implied module name

**MachV Emitter**:
The reusable machine-code emitter that lowers **MachV** into bytes, relocations, stack maps, and debug metadata.
_Avoid_: x64_emit as a first split, aarch64_emit as a first split, machv_codegen, codegen, asm, wasmoon JIT emitter, runtime fixup emitter

**Wasmoon JIT**:
The Wasmoon-specific native execution integration that resolves runtime symbols, executable memory, host calls, VMContext state, traps, and helper bindings.
_Avoid_: generic emitter, compiler backend

**JIT FFI**:
The native C and assembly glue used by **Wasmoon JIT** for executable memory, traps, GC, WASI, stack switching, VMContext access, and host calls.
_Avoid_: generic native runtime, exec_mem module before reuse exists

**Cwasm Artifact**:
The Wasmoon-owned precompiled module format for cached or ahead-of-time native execution metadata.
_Avoid_: MachV emitter output, generic object format

## Relationships

- **Wasm Core** owns WebAssembly specification concepts but does not depend on **MilkIR**, **MachV**, JIT, or the **Wasmoon Runtime**.
- A **Wasm Frontend** lowers one **Wasmoon Runtime** module into one or more **MilkIR** functions.
- A **Wasm Frontend** uses an **Embedding Environment** to translate WebAssembly memories, tables, globals, references, and runtime operations.
- **Runtime Lowering** may introduce external symbols, helper calls, hidden parameters, and runtime-state operands, but not WebAssembly-specific core opcodes.
- A **Frontend Type System** may inform **Runtime Lowering**, but does not become the **MilkIR** type system.
- **MilkIR Core** starts as the smallest useful subset and uses **Completeness TODO** comments for known gaps.
- A **Completeness TODO** documents an accepted limitation, but is not itself a correctness gate.
- **MilkIR-MachV Lowering** lowers one **MilkIR** function into one **MachV** function.
- **Machine Targets** own **ABI Policy**, while **MachV** only represents registers, constraints, calls, clobbers, and stack effects.
- A **MachV Register Allocation Adapter** lets **Register Allocation** allocate **MachV** without depending on **MachV** instruction data structures.
- A **MachV Emitter** produces generic relocation and metadata records; **Wasmoon JIT** resolves those records to Wasmoon runtime helpers and executable memory.
- A **Cwasm Artifact** may wrap **MachV Emitter** output with Wasmoon function indices, imports, traps, debug mapping, and runtime metadata.
- **JIT FFI** belongs to **Wasmoon JIT** until a small generic executable-memory API has proven reuse.
- The **Wasmoon Runtime** depends on compiler infrastructure modules, but compiler infrastructure modules do not depend on the **Wasmoon Runtime**.

## Example dialogue

> **Dev:** "Should `memory.grow` be an opcode in **MilkIR**?"
> **Domain expert:** "No, WebAssembly operations belong in the **Wasm Frontend** unless they are general compiler concepts."

## Flagged ambiguities

- "IR" previously referred to a WebAssembly-shaped SSA representation; resolved: use **MilkIR** for the reusable compiler IR and **Wasm Frontend** for WebAssembly-specific lowering.
- WebAssembly-specific operations previously appeared as core IR concepts; resolved: lower them through the **Embedding Environment** unless they are general compiler concepts.
- Runtime-specific behavior previously leaked through dedicated IR opcodes; resolved: represent it with **Runtime Lowering** into ordinary **MilkIR** constructs.
- WebAssembly reference and GC types previously appeared as IR-level concepts; resolved: keep them in the **Frontend Type System** and lower them to generic value carriers plus metadata.
- WebAssembly model ownership was previously unclear; resolved: **Wasm Core** owns spec-level concepts and must not depend on compiler backend or runtime modules.
- The reusable IR scope was previously ambiguous; resolved: **MilkIR Core** is intentionally minimal, and incomplete areas must be marked with **Completeness TODO** comments.
- TODO policy was ambiguous; resolved: **Completeness TODO** comments are required for known gaps but are not part of the current correctness gates.
- "VCode" previously named both the current Wasmoon machine IR and the reusable machine layer; resolved: use **MachV** for the reusable virtual-register machine IR.
- Instruction selection ownership was previously unclear; resolved: **milkir_machv** bridges **MilkIR** and **MachV** instead of putting target lowering into either core module.
- Target packaging was ambiguous; resolved: use ISA-specific modules such as `x64_target` and `aarch64_target`, not generic `backend` or `isa_backend` packages.
- ABI ownership was previously mixed into the machine layer; resolved: **Machine Targets** own **ABI Policy** and **MachV** only expresses the policy's effects.
- Register allocation previously depended on concrete VCode structures; resolved: keep **Register Allocation** independent and put **MachV**-specific projection and rewriting in a **MachV Register Allocation Adapter**.
- Machine-code emission previously mixed byte encoding with Wasmoon runtime fixups; resolved: **MachV Emitter** emits generic relocation records and **Wasmoon JIT** owns runtime symbol resolution.
- Emitter packaging was ambiguous; resolved: keep one `machv_emit` package with ISA-specific internals instead of first splitting `x64_emit` or `aarch64_emit`.
- Precompiled output ownership was ambiguous; resolved: **Cwasm Artifact** belongs to **Wasmoon JIT**, not **MachV Emitter**.
- Native JIT glue ownership was ambiguous; resolved: **JIT FFI** remains in **Wasmoon JIT** for the first split instead of creating a generic executable-memory module.
- "Wasmoon Runtime" names an execution-system concept, not a required package named `wasmoon_runtime`; resolved: keep the package name decision separate from the concept.
