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
A reusable, target-neutral low-level virtual-register intermediate representation with single-definition values and block parameters. Every native JIT path passes through **MachV** before target-specific lowering.
_Avoid_: target VCode, target-bound IR, portable execution target

**MilkIR-MachV Lowering**:
The target-neutral layer that lowers **MilkIR** into **MachV** without choosing host instructions, calling conventions, physical registers, or target constraints.
_Avoid_: instruction selection, target backend, wasmoon JIT

**Semantic Legalization**:
The target-neutral normalization that removes source or dialect concepts and makes value widths, effects, traps, memory behavior, and call semantics explicit before values enter **MachV**.
_Avoid_: instruction selection, ABI lowering, target expansion

**Semantic Superinstruction**:
A **MachV** operation whose decomposition would change observable rounding, atomicity, trap behavior, or effect boundaries.
_Avoid_: target fusion, encoding shortcut, instruction-count optimization

**Semantic Memory Access**:
A target-neutral **MachV** load or store described by a computed address, access width, value behavior, byte offset, and endianness rather than a host addressing mode.
_Avoid_: target load form, Wasm memory instruction, encoded addressing mode

**MachV Target Lowering**:
The target-owned translation from **MachV** into an AArch64- or AMD64-specific **Target VCode**.
_Avoid_: MachV opcode dialect, host-tagged MachV

**Target Legalization**:
The target-owned expansion of a valid **MachV** operation into one or more legal instructions in **Target VCode**.
_Avoid_: semantic legalization, MachV lowering

**Target VCode**:
A shared virtual-register function and control-flow structure parameterized by a closed, target-owned instruction type such as `AArch64Inst` or `AMD64Inst`.
_Avoid_: MachV, shared target opcode, union of machine dialects

**Portable Execution Target**:
An optional downstream target that lowers **MachV** into interpreter-oriented bytecode with its own instruction set and execution contract.
_Avoid_: MachV bytecode, MachV VM, production MachV interpreter

**ABI Policy**:
The target and embedding-specific rules for argument registers, return registers, callee-saved registers, caller-saved registers, stack layout, and call clobbers.
_Avoid_: MachV core policy

**Register Allocation**:
The target-independent allocation algorithm that assigns virtual registers or spills in **Target VCode** through a shared abstract program model.
_Avoid_: regalloc_core, VCode regalloc, machine regalloc

**Wasmoon Runtime**:
The WebAssembly execution system that owns Wasm validation, instantiation, host integration, and runtime semantics.
_Avoid_: compiler infrastructure, wasmoon_runtime as an implied module name

**Target Emitter**:
The machine-target-owned encoder that turns allocated **Target VCode** into bytes and generic metadata.
_Avoid_: MachV emitter, wasmoon JIT emitter, runtime fixup emitter

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
- **Semantic Legalization** completes during **MilkIR-MachV Lowering** without asking whether a host ISA has a matching instruction.
- A **Semantic Superinstruction** belongs in **MachV** only when ordinary operations cannot reproduce its semantics without loss.
- A **Semantic Memory Access** carries narrow-load extension semantics and memory effects, while target lowering selects an addressing mode.
- **MachV** preserves single-definition virtual registers and block parameters through target-neutral lowering.
- **MachV Target Lowering** lowers every **MachV** function into **Target VCode** parameterized by the selected target's instruction type.
- **Target Legalization** may expand one semantic **MachV** operation into multiple target instructions.
- **Machine Targets** own **ABI Policy**; **MachV** does not encode host instructions, physical registers, calling conventions, or target constraints.
- **Target VCode** shares function, block, control-flow, virtual-register, and allocation structure without sharing target instructions.
- A **Portable Execution Target** may consume **MachV** without turning **MachV** itself into a stable bytecode or VM contract.
- **Register Allocation** runs after **MachV Target Lowering** and before a **Target Emitter**.
- A **Target Emitter** produces generic relocation and metadata records; **Wasmoon JIT** resolves those records to Wasmoon runtime helpers and executable memory.
- A **Cwasm Artifact** may wrap **Target Emitter** output with Wasmoon function indices, imports, traps, debug mapping, and runtime metadata.
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
- Instruction selection ownership was previously unclear; resolved: **MilkIR-MachV Lowering** is target-neutral, while **MachV Target Lowering** owns host instruction selection.
- Legalization ownership was previously unclear; resolved: **Semantic Legalization** produces target-neutral **MachV**, while **Target Legalization** expands its operations into legal **Target VCode**.
- Fused-operation ownership was previously unclear; resolved: only a **Semantic Superinstruction** may enter **MachV**, while performance-only fusion belongs to target lowering.
- Memory-operation ownership was previously unclear; resolved: **MachV** uses parameterized **Semantic Memory Access** operations and a distinct atomic family, while target addressing modes belong to **Target VCode**.
- SSA destruction ownership was previously unclear; resolved: **MachV** retains single-definition virtual registers and block parameters, while target-specific constraints and copy insertion begin in **Target VCode**.
- Portable execution ownership was previously unclear; resolved: **MachV** remains a compiler intermediate representation, while any production bytecode and interpreter belong to a separate **Portable Execution Target**.
- Target packaging was ambiguous; resolved: use ISA-specific modules such as `x64_target` and `aarch64_target`, not generic `backend` or `isa_backend` packages.
- ABI ownership was previously mixed into the machine layer; resolved: **Machine Targets** own **ABI Policy** and apply it after **MachV**.
- Register-allocation placement was reopened; resolved: **Register Allocation** consumes the target-specific representation produced by **MachV Target Lowering**, never **MachV** itself.
- Machine-code-emission ownership has been reopened: decide the interface between target-specific representations, byte encoding, generic metadata, and **Wasmoon JIT** runtime resolution.
- Precompiled output ownership was ambiguous; resolved: **Cwasm Artifact** belongs to **Wasmoon JIT**, not a **Target Emitter**.
- Native JIT glue ownership was ambiguous; resolved: **JIT FFI** remains in **Wasmoon JIT** for the first split instead of creating a generic executable-memory module.
- "Wasmoon Runtime" names an execution-system concept, not a required package named `wasmoon_runtime`; resolved: keep the package name decision separate from the concept.
