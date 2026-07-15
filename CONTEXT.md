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

**MachV Value Type**:
One of `I32`, `I64`, `F32`, `F64`, `V128`, `Ptr64`, or `GcRef64`, preserving exact target-neutral width and carrier meaning without choosing a target register bank or location.
_Avoid_: register class, ABI value location, MilkIR type

**MachV Managed Reference**:
A `GcRef64` **MachV Value** that may be null and must remain identifiable as a GC root through target lowering and allocation.
_Avoid_: ordinary pointer, opaque integer carrier, source-language reference type

**MachV Constant**:
A bit-exact, typed semantic definition of a **MachV Value**, including symbolic addresses and distinct null pointer or managed-reference values.
_Avoid_: target immediate, raw process address, constant-pool entry

**MachV Value**:
An opaque function-owned handle to one single-definition value whose type and construction facts are held canonically by its **MachV** function.
_Avoid_: raw value id, publicly constructed virtual register, duplicated typed tuple

**MachV Signature**:
The ordered parameter and result **MachV Value Type** contract of one function or semantic call, independent of host ABI placement and effects.
_Avoid_: calling convention, ABI signature, register-class signature

**MachV Edge**:
A target-neutral control-flow connection from one terminator to a block, carrying ordered SSA arguments that match the target block parameters.
_Avoid_: bare block id, synthetic edge block, implicit phi input

**MachV Control-Flow Graph**:
The rooted, fully reachable graph of semantic MachV blocks connected by **MachV Edges**, independent of final machine-code layout.
_Avoid_: block forest, physical block layout, bytecode offset graph

**MachV Block**:
An opaque function-owned handle to one basic block whose parameters, instructions, terminator, and order are held canonically by its MachV function.
_Avoid_: raw block id, publicly mutable block object, target label

**MachV Instruction**:
An opaque function-owned handle to one semantic operation with canonical operands, results, and metadata, appearing exactly once in one **MachV Block**.
_Avoid_: inline mutable instruction object, block-index pair, reusable instruction record

**MachV SSA**:
The single-definition discipline in which function parameters, block parameters, and instruction results define MachV Values, and every use is dominated by its definition.
_Avoid_: phi instruction, target copy form, register-allocation SSA

**MachV Program Order**:
The observable baseline order defined by each block's ordered MachV Instructions followed by its terminator, constrained by canonical effect and trap summaries.
_Avoid_: effect-token chain, target instruction schedule, array order without semantics

**MachV Terminator**:
The final semantic operation of a **MachV Block**, chosen from jump, conditional branch, integer switch, return, tail call, or structured trap.
_Avoid_: compare-branch encoding, fallthrough marker, target jump form

**MachV Mutation Boundary**:
The function-owned editing seam that atomically rejects invalid local entities and shapes while permitting incomplete whole-function state until an explicit verifier checkpoint.
_Avoid_: direct canonical-array mutation, silent construction failure, always-valid builder state

**MachV Verifier**:
The target-neutral, read-only checkpoint that validates canonical entity integrity, semantic contracts, rooted control flow, and MachV SSA dominance.
_Avoid_: target verifier, repairing validator, permanent verified state

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

**Semantic Call**:
A target-neutral **MachV** call described by its callee, signature, explicit arguments and results, call kind, and effects rather than native ABI placement.
_Avoid_: ABI call sequence, fixed-register call, conditional helper fusion

**Semantic Trap**:
A target-neutral **MachV** termination carrying a structured reason; implicit trap conditions remain semantic properties of the operations that can trigger them.
_Avoid_: conditional trap fusion, target trap payload, hardware trap instruction

**Semantic Scalar Operation**:
A target-neutral **MachV** arithmetic, comparison, or conversion whose exact widths and behavior-changing modes are explicit and whose observable status outputs are ordinary values.
_Avoid_: machine instruction form, flag-setting operation, immediate encoding variant

**Semantic Vector Operation**:
A target-neutral **MachV** `V128` operation whose lane interpretation is explicit only where it changes meaning and whose behavior is independent of a host SIMD instruction set.
_Avoid_: target SIMD intrinsic, opcode-per-lane-shape, speculative wide vector

**MachV Target Lowering**:
The all-or-nothing, target-owned translation from **MachV** into a complete, verified AArch64- or AMD64-specific **Target VCode**; failure exposes no partial output.
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

**Allocated Location**:
A target register or frame slot assigned to a **Target VCode** virtual value by **Register Allocation**.
_Avoid_: MachV value location, semantic stack object, ABI signature fact

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
- Every function parameter, block parameter, and instruction result in **MachV** has a **MachV Value Type**; target lowering maps that type to a target register class.
- A **MachV Value** is created through its function's interface, and all consumers resolve its **MachV Value Type** from that function's canonical value table.
- A **MachV Value** has an in-memory function owner identity that rejects cross-function use but does not enter printing or serialization.
- Function parameters are the initial **MachV Values** declared by a **MachV Signature**; a hidden context, when needed, is an explicit `Ptr64` parameter.
- Returns and **Semantic Calls** match their **MachV Signature** exactly, while effects, safepoints, and unwind behavior remain separate semantic summaries.
- Every successor-bearing MachV terminator uses a **MachV Edge**, so jumps, conditional branches, and multi-way branches pass block arguments through the same interface.
- Every verified MachV function has one entry block with no incoming edge or block parameters, and every other block is reachable from it.
- A **MachV Block** is created and resolved through its function, and every **MachV Edge** target must carry the same private function owner identity.
- A **MachV Instruction** is created and resolved through its function, has stable identity until deletion, and occupies exactly one ordered position in one **MachV Block**.
- In **MachV SSA**, function parameters are initial values, block parameters are defined at block entry, instruction results are defined after their instruction, and edge arguments are parallel uses at the source terminator.
- **MachV SSA** admits critical edges but no phi instructions; Target VCode lowering may split edges and insert parallel copies when applying target constraints.
- **MachV Program Order** permits reordering only when SSA, memory effects, traps, unwind behavior, safepoints, and all other observable behavior remain equivalent.
- Every **MachV Block** has exactly one **MachV Terminator**; its successor-bearing forms use **MachV Edges**, and no instruction follows it.
- A **MachV Terminator** expresses only semantic control flow; compare fusion, immediate branches, fallthrough, jump tables, and encoded labels belong to Target VCode or emission.
- The **MachV Mutation Boundary** rejects foreign, deleted, duplicated, or locally ill-typed entities before changing state; reachability and dominance are whole-function verifier concerns.
- The **MachV Verifier** deterministically reports the first structured error without target or ABI context, mutation, repair, or abort.
- **MachV Control-Flow Graph** order expresses semantics and SSA relationships; fallthrough selection, label offsets, branch relaxation, and final block layout belong downstream.
- `Ptr64` and `GcRef64` are always 64-bit carriers; only `GcRef64` is a **MachV Managed Reference**.
- A **MachV Constant** produces an ordinary SSA value; target lowering may select immediates, relocations, or constant-pool loads without changing its meaning.
- **Semantic Legalization** completes during **MilkIR-MachV Lowering** without asking whether a host ISA has a matching instruction.
- A **Semantic Superinstruction** belongs in **MachV** only when ordinary operations cannot reproduce its semantics without loss.
- A **Semantic Memory Access** carries narrow-load extension semantics and memory effects, while target lowering selects an addressing mode.
- A **Semantic Call** preserves direct, external, or indirect callee identity and normal or tail-call meaning, while target lowering applies **ABI Policy**.
- A **Semantic Trap** ends its block unconditionally; conditional traps use ordinary control flow, while target lowering selects checks, hardware traps, or helper calls that preserve the reason.
- A **Semantic Scalar Operation** preserves signedness, rounding, saturation, and trapping behavior where they affect meaning; target lowering chooses immediates, instruction forms, and machine flags.
- A **Semantic Vector Operation** uses parameterized lane shapes and semantic shuffle or memory behavior, while target lowering chooses native SIMD instructions or expansions.
- **MachV** preserves single-definition virtual registers and block parameters through target-neutral lowering.
- **MachV Target Lowering** lowers every **MachV** function into **Target VCode** parameterized by the selected target's instruction type.
- Successful **MachV Target Lowering** returns a complete target-owned function with no mutable aliases into **MachV**; its private partial builder is discarded on failure, and later output mutation requires revalidation.
- **Target Legalization** may expand one semantic **MachV** operation into multiple target instructions.
- **Machine Targets** own **ABI Policy**; **MachV** does not encode host instructions, physical registers, calling conventions, or target constraints.
- **Target VCode** shares function, block, control-flow, virtual-register, and allocation structure without sharing target instructions.
- A **Portable Execution Target** may consume **MachV** without turning **MachV** itself into a stable bytecode or VM contract.
- **Register Allocation** runs after **MachV Target Lowering** and before a **Target Emitter**.
- **MachV** values have no locations; **Allocated Location**, spill slots, ABI areas, and stack-pointer operations begin after **MachV Target Lowering**.
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
- Value typing previously used target-like register classes inside **MachV**; resolved: **MachV Value Type** preserves exact semantics, while register classes begin in **Target VCode**.
- Value identity previously duplicated ids and classes in public virtual-register records; resolved: a **MachV Value** is opaque and its function owns the sole value-type table.
- Cross-function value identity was previously indistinguishable when dense ids collided; resolved: **MachV Value** handles carry a private function owner identity, and cloning or deserialization remaps values under a fresh owner.
- Pointer and reference carriers previously collapsed into one register class; resolved: `Ptr64` denotes untraced addresses and handles, while `GcRef64` preserves managed-root identity without importing source-language reference kinds.
- Constant representation previously mixed semantic values with target load and immediate forms; resolved: **MachV Constant** carries bit-exact typed meaning, while target encoding and storage belong downstream.
- Instruction selection ownership was previously unclear; resolved: **MilkIR-MachV Lowering** is target-neutral, while **MachV Target Lowering** owns host instruction selection.
- Legalization ownership was previously unclear; resolved: **Semantic Legalization** produces target-neutral **MachV**, while **Target Legalization** expands its operations into legal **Target VCode**.
- Fused-operation ownership was previously unclear; resolved: only a **Semantic Superinstruction** may enter **MachV**, while performance-only fusion belongs to target lowering.
- Memory-operation ownership was previously unclear; resolved: **MachV** uses parameterized **Semantic Memory Access** operations and a distinct atomic family, while target addressing modes belong to **Target VCode**.
- Call ownership was previously unclear; resolved: **MachV** owns **Semantic Call** meaning and explicit values, while **Target VCode** owns ABI placement, physical clobbers, outgoing stack layout, and prologue or epilogue details.
- Trap ownership was previously unclear; resolved: **MachV** owns structured **Semantic Trap** reasons and operation-level trap conditions, while conditional trap fusion and target trap encoding belong to **Target VCode**.
- Scalar-operation ownership was previously unclear; resolved: **MachV** owns precisely typed arithmetic and conversion meaning, while condition flags, fixed registers, shifted operands, and immediate encodings belong to **Target VCode**.
- Vector-operation ownership was previously unclear; resolved: **MachV** currently owns only target-neutral `V128` meaning, while target SIMD forms and wider or scalable vectors remain outside the contract.
- SSA destruction ownership was previously unclear; resolved: **MachV** retains single-definition virtual registers and block parameters, while target-specific constraints and copy insertion begin in **Target VCode**.
- Portable execution ownership was previously unclear; resolved: **MachV** remains a compiler intermediate representation, while any production bytecode and interpreter belong to a separate **Portable Execution Target**.
- Target packaging was ambiguous; resolved: use ISA-specific modules such as `x64_target` and `aarch64_target`, not generic `backend` or `isa_backend` packages.
- ABI ownership was previously mixed into the machine layer; resolved: **Machine Targets** own **ABI Policy** and apply it after **MachV**.
- Register-allocation placement was reopened; resolved: **Register Allocation** consumes the target-specific representation produced by **MachV Target Lowering**, never **MachV** itself.
- Target-lowering output atomicity was unclear; resolved: success returns complete, verified, target-owned **Target VCode**, while failure returns a structured error without exposing partial builder state.
- Value-location ownership was previously mixed into **MachV**; resolved: MachV safepoints and operations reference values, while **Allocated Location** and frame layout belong downstream.
- Function signatures previously carried ABI result locations, stack counts, and placement facts; resolved: a **MachV Signature** contains only ordered parameter and result types, while ABI facts belong downstream.
- Conditional and multi-way branches previously carried only target ids, forcing producers to insert jump-only blocks for SSA arguments; resolved: every successor is a **MachV Edge** with explicit arguments.
- Reachability and layout were previously conflated; resolved: a verified **MachV Control-Flow Graph** is rooted and fully reachable, while physical block layout is selected downstream.
- Block identity previously used public integer ids and independently mutable block objects; resolved: a **MachV Block** is an opaque function-owned handle backed by the function's canonical dense block table.
- Instructions previously existed as independently mutable records whose identity was their array position; resolved: a **MachV Instruction** is an opaque function-owned handle backed by canonical instruction data and unique block membership.
- SSA validity previously depended on partial register-id and block-order checks; resolved: **MachV SSA** requires one canonical definition per value and dominance at every instruction, edge, and terminator use.
- Effect order previously depended on scattered opcode knowledge; resolved: **MachV Program Order** plus canonical operation summaries defines observable ordering without introducing effect-token values.
- Terminators previously mixed semantic control flow with AArch64 and AMD64 branch forms; resolved: **MachV Terminator** has one minimal target-neutral vocabulary, while encoded branch selection belongs downstream.
- Mutation safety previously depended on callers repairing directly mutable arrays; resolved: the **MachV Mutation Boundary** is locally atomic, while explicit verifier checkpoints validate cross-entity invariants.
- Verification previously mixed partial SSA checks with target register policy; resolved: the **MachV Verifier** validates only the complete target-neutral MachV contract, while target representations have their own verifiers.
- Machine-code-emission ownership has been reopened: decide the interface between target-specific representations, byte encoding, generic metadata, and **Wasmoon JIT** runtime resolution.
- Precompiled output ownership was ambiguous; resolved: **Cwasm Artifact** belongs to **Wasmoon JIT**, not a **Target Emitter**.
- Native JIT glue ownership was ambiguous; resolved: **JIT FFI** remains in **Wasmoon JIT** for the first split instead of creating a generic executable-memory module.
- "Wasmoon Runtime" names an execution-system concept, not a required package named `wasmoon_runtime`; resolved: keep the package name decision separate from the concept.
