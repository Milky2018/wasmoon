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

**MachV Function**:
The function-scoped unit of target-neutral MachV structure, semantics, control flow, and SSA consumed by target lowering.
_Avoid_: verified wrapper, target VCode function, machine-code function

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

**Verification Checkpoint**:
A representation-owned deterministic read-only validation performed by every public transformation on entry and before successful output, without persistent verified state or a caller-controlled bypass.
_Avoid_: caller-managed validation, mutable validator closure, disabled safety check

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

**External Symbol Identity**:
An embedding-provided stable opaque identity for a foreign callee or datum that reusable compiler infrastructure preserves without knowing its runtime name or address.
_Avoid_: Wasmoon helper name, resolved address, lowering callback

**Call Behavior Summary**:
The target-neutral conservative facts describing a **Semantic Call**'s memory effects, trap and unwind behavior, and GC or cancellation safepoints independently of its **Call Protocol**.
_Avoid_: ABI-derived behavior, symbol-name inference, emitter policy

**Logical Call Contract**:
The ordered typed parameters, explicit argument values, and logical results required to invoke a **Semantic Call**, independent of native register, stack, or hidden return-area placement.
_Avoid_: native call sequence, argument-register layout, stack-call frame

**True Tail Call**:
An internal **Semantic Call** that transfers control without growing the logical call stack, forwarding the current return contract directly to its callee.
_Avoid_: call followed by return, platform tail-call promise, fresh return area

**Call Protocol**:
The target-neutral choice between an embedding-defined internal calling convention and the host platform calling convention for a MachV function entry or **Semantic Call**.
_Avoid_: callee identity, physical ABI layout, opaque convention registry

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

**Target Lowering Context**:
An immutable, statically typed set of target facts and compilation policy used by one machine target during **MachV Target Lowering**.
_Avoid_: service locator, runtime resolver, dynamic target interface

**Target Legalization**:
The target-owned expansion of a valid **MachV** operation into one or more legal instructions in **Target VCode**.
_Avoid_: semantic legalization, MachV lowering

**Target VCode**:
A shared virtual-register function and control-flow structure parameterized by a closed, target-owned instruction type such as `AArch64Inst` or `AMD64Inst`.
_Avoid_: MachV, shared target opcode, union of machine dialects

**Target VCode SSA**:
The strict single-definition form retained by **Target VCode** through register-allocation input, including block parameters and typed edge arguments.
_Avoid_: pre-allocation multiple definitions, physical-register form, edge-copy mutation

**Target VCode Verifier**:
The static target checkpoint that composes shared Target VCode structure and SSA validation with exhaustive target-owned instruction, feature, ABI, and emitter legality checks.
_Avoid_: dynamic target callback, shared target opcode verifier, emitter abort

**Allocated Function**:
The checkpoint state consisting of one unchanged Target VCode function and its separate structurally bound Allocation.
_Avoid_: rewritten physical VCode, allocated MachV, verified wrapper

**Portable Execution Target**:
An optional downstream target that lowers **MachV** into interpreter-oriented bytecode with its own instruction set and execution contract.
_Avoid_: MachV bytecode, MachV VM, production MachV interpreter

**ABI Policy**:
The target and embedding-specific rules for argument registers, return registers, callee-saved registers, caller-saved registers, stack layout, and call clobbers.
_Avoid_: MachV core policy

**Internal ABI Contract**:
The embedding-owned cross-language agreement for its internal **Call Protocol**, including execution-environment and reserved runtime register roles that compiled code, native stubs, and host glue must share.
_Avoid_: MachV context layout, platform ABI, target lowering implementation

**Wasmoon JIT ABI Contract**:
The versioned product contract that contains Wasmoon's **Internal ABI Contract** together with its VMContext layout, runtime-symbol identities, native trap and stack-map encodings, unwind agreement, and persistent runtime roles.
_Avoid_: VMContext instance, target ABI convention, duplicated MoonBit and C constants

**Target ABI Convention**:
A machine-target-owned, validated physical realization of one **Call Protocol** used to derive concrete call layouts during target lowering.
_Avoid_: MachV signature, runtime ABI registry, unvalidated embedding layout

**Persistent ABI Role**:
An embedding-selected, target-validated callee-saved register role represented as a precolored Target VCode value only in functions that use it.
_Avoid_: MachV physical value, unconditional register reservation, caller-saved cache

**Call Layout**:
The target-owned physical placement derived for one logical function entry or **Semantic Call** from its signature and **Target ABI Convention**.
_Avoid_: MachV call contract, caller-authored placement, persistent ABI registry entry

**Return Area**:
A caller-owned target stack object through which a **Call Layout** transfers logical results that do not fit the convention's result registers.
_Avoid_: MachV result pointer, source-level aggregate, fixed SP offset

**Incoming Argument Slot**:
A target-level symbolic view of a stack argument residing in the caller's frame and made available to a callee by its **Call Layout**.
_Avoid_: callee stack object, MachV stack parameter, fixed frame offset

**Outgoing Call Area**:
A caller-owned target stack area sized for the function's maximum call-site requirement, including required shadow space, stack arguments, and return areas.
_Avoid_: MachV outgoing size, per-call dynamic stack adjustment, fixed SP offset

**Frame Layout**:
The target-owned post-allocation placement of spills, stack objects, callee saves, outgoing areas, and frame metadata used to emit a function's stack frame.
_Avoid_: MachV frame state, pre-allocation offset, prologue opcode

**Frame Layout Verifier**:
The target checkpoint that proves one **Frame Layout** is complete, non-overlapping, ABI-aligned, metadata-consistent, and encodable for its structurally bound Target VCode and Allocation.
_Avoid_: emitter stack assertion, unbound frame offsets, post-write validation

**Code Object Verifier**:
The target checkpoint that validates a complete unlinked machine-code artifact's labels, relocations, sections, instruction-boundary metadata, architecture, and feature contract before the artifact leaves emission.
_Avoid_: linked-code verifier, production disassembly round trip, partial-buffer validation

**Framed Function**:
The checkpoint state consisting of an **Allocated Function** and its target-owned **Frame Layout**.
_Avoid_: frame-bearing MachV, emitter state, verified wrapper

**Unlinked Code Object**:
The complete target-specific bytes and generic relocation and metadata records produced before Wasmoon JIT resolves runtime addresses or installs executable memory.
_Avoid_: linked image, executable memory, partial emission buffer

**Register Allocation**:
The target-independent allocation algorithm that assigns virtual registers or spills in **Target VCode** through a shared abstract program model.
_Avoid_: regalloc_core, VCode regalloc, machine regalloc

**Allocation Binding**:
The structural association between one Target VCode function and its allocation through private function ownership and stable instruction, operand, value, edge, and program-point identities.
_Avoid_: raw array position, version stamp, cross-function allocation

**Allocation Verifier**:
The target checkpoint that combines algorithm-independent allocation correctness with the selected machine environment's physical-register, reserved-role, scratch, and callee-save rules.
_Avoid_: allocator-specific assertion, emitter allocation check, aborting checker

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

**Wasmoon JIT Compiler**:
The product-owned compiler module configured once for a target and immutable policy that compiles verified MilkIR through every mandatory native stage into an **Unlinked Code Object**.
_Avoid_: runtime linker, stage-by-stage controller, target plugin

**Module Compilation**:
The immutable Wasmoon compilation context that binds one validated module's identity, semantic features, function and import identities, signatures, and module layout while producing independent function code objects.
_Avoid_: Store instance, compiler IR module, installed native module

**JIT Pipeline Error**:
The Wasmoon JIT failure that preserves one stage-owned structured compiler error and its precise site while remaining distinct from cooperative cancellation.
_Avoid_: string-only diagnostic, backend abort, cancelled compilation

**JIT FFI**:
The native C and assembly glue used by **Wasmoon JIT** for executable memory, traps, GC, WASI, stack switching, VMContext access, and host calls.
_Avoid_: generic native runtime, exec_mem module before reuse exists

**JIT Code Installation**:
The Wasmoon-owned all-or-nothing transaction that resolves and patches an **Unlinked Code Object**, registers its runtime metadata, makes its memory executable, and publishes its entry points only at commit.
_Avoid_: incremental function publication, executable allocator call, linker-only step

**Installed Code**:
The opaque Wasmoon result that owns executable mappings and their trap, GC, unwind, debug, and address-registration lifetimes after **JIT Code Installation** commits.
_Avoid_: raw function pointer array, linked byte buffer, unmanaged executable page

**Cwasm Artifact**:
The Wasmoon-owned persistent form of **Unlinked Code Objects** plus module and compatibility metadata, without compiler IR, resolved process addresses, or executable memory.
_Avoid_: linked code cache, serialized IR, process image

**Artifact Compatibility Manifest**:
The strict Wasmoon identity that binds a **Cwasm Artifact** to its format, target and required features, JIT ABI, code-generation revision, source module semantics, and compilation policy.
_Avoid_: best-effort loader, runtime-address table, implicit compatibility

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
- A **Logical Call Contract** includes an explicit ordinary `Ptr64` execution-environment value when the callee requires one, but never names or describes a product VMContext; hidden return-area pointers remain ABI details.
- Every MachV function entry and **Semantic Call** explicitly selects `Internal` or `Platform` **Call Protocol**, independently of whether its callee is direct, indirect, or external.
- A **True Tail Call** is an `Internal`-protocol MachV terminator whose logical results exactly match its enclosing function; target lowering must preserve bounded-stack behavior and forward the existing return area rather than falling back to a normal call.
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
- The **MachV Verifier** covers function ownership, signatures and types, rooted CFG edges, strict SSA dominance, terminators, semantic operation contracts, and behavior summaries, but never target legality or ABI state.
- Every public compiler transformation owns entry and exit **Verification Checkpoints**; ordinary mutable representations are revalidated at the next public seam without acquiring permanent verified state.
- The native checkpoint sequence is **MachV Function**, Target VCode SSA, **Allocated Function**, **Framed Function**, then **Unlinked Code Object**; these names describe ordinary data at public seams rather than wrapper or frozen types.
- **MachV Control-Flow Graph** order expresses semantics and SSA relationships; fallthrough selection, label offsets, branch relaxation, and final block layout belong downstream.
- `Ptr64` and `GcRef64` are always 64-bit carriers; only `GcRef64` is a **MachV Managed Reference**.
- A **MachV Constant** produces an ordinary SSA value; target lowering may select immediates, relocations, or constant-pool loads without changing its meaning.
- **Semantic Legalization** completes during **MilkIR-MachV Lowering** without asking whether a host ISA has a matching instruction.
- A **Semantic Superinstruction** belongs in **MachV** only when ordinary operations cannot reproduce its semantics without loss.
- A **Semantic Memory Access** carries narrow-load extension semantics and memory effects, while target lowering selects an addressing mode.
- A **Semantic Call** preserves direct, external, or indirect callee identity and normal or tail-call meaning, while target lowering applies **ABI Policy**.
- An **External Symbol Identity** remains unresolved through MachV, Target VCode, allocation, and target emission; Wasmoon JIT owns runtime naming, address resolution, and artifact compatibility.
- A **Call Behavior Summary** is explicit and conservative by default; optimization, safepoint handling, and metadata preservation consume it without inferring behavior from protocol, callee form, or symbol identity.
- A **Semantic Trap** ends its block unconditionally; conditional traps use ordinary control flow, while target lowering selects checks, hardware traps, or helper calls that preserve the reason.
- A **Semantic Scalar Operation** preserves signedness, rounding, saturation, and trapping behavior where they affect meaning; target lowering chooses immediates, instruction forms, and machine flags.
- A **Semantic Vector Operation** uses parameterized lane shapes and semantic shuffle or memory behavior, while target lowering chooses native SIMD instructions or expansions.
- **MachV** preserves single-definition virtual registers and block parameters through target-neutral lowering.
- **MachV Target Lowering** lowers every **MachV** function into **Target VCode** parameterized by the selected target's instruction type.
- Successful **MachV Target Lowering** returns a complete target-owned function with no mutable aliases into **MachV**; its private partial builder is discarded on failure, and later output mutation requires revalidation.
- Each target owns a statically typed **Target Lowering Context**; lowering uses no shared ISA union, arbitrary callbacks, service lookup, or per-instruction dynamic dispatch.
- A **Target Lowering Context** may carry immutable CPU features, tuning policy, and code model, but not runtime address resolution, executable memory, register allocation, or emission services.
- Each machine target owns whole-function traversal, instruction selection, local pattern fusion, and **Target Legalization**; the shared Target VCode layer provides compact storage, dense handles, a typed builder, and invariant checks rather than a per-operation lowering framework.
- Target lowering preallocates from MachV function counts and uses dense constant-time mappings. Its common path remains near-linear, while extra target-owned analyses require a concrete optimization benefit.
- Target lowering reports target-owned structured failures with a MachV source site and phase; its public interface never aborts the host, silently omits an operation, or emits placeholder code for a lowering failure.
- AArch64 and AMD64 expose separate statically typed lowering entry points. Wasmoon JIT branches on the selected machine target once, then keeps lowering, allocation, and emission specialized without a runtime target union or target-lowering trait.
- Target lowering borrows verified **MachV** through read-only dense-indexed queries without cloning or mutating it, and constructs independent **Target VCode** storage without retaining aliases into MachV-owned collections.
- **Target VCode** stores allocation operands, constraints, timing, ties, and clobbers once in compact shared side tables. Register allocation reads those tables directly and never reconstructs facts by matching target instructions.
- Register allocation leaves virtual **Target VCode** unchanged and returns a separate dense allocation result; the statically typed target emitter consumes both and interleaves allocation edits at stable program points.
- An **Allocation Binding** is verified as a complete structural bijection against the current Target VCode rather than inferred from raw indices, mutation history, or a version stamp.
- The **Allocation Verifier** rechecks Target VCode, generic liveness and constraint correctness, and target machine-environment legality before frame planning.
- Source locations, structured trap reasons, cancellation and GC safepoints, safepoint `GcRef64` values, and unresolved symbol identities cross target lowering as compact metadata keyed by stable Target VCode instruction handles.
- Relocation encodings, constant-pool layout, branch relaxation, veneers, final code offsets, and runtime addresses do not enter the shared Target VCode shell; target emission and Wasmoon linking own them.
- **Target Legalization** may expand one semantic **MachV** operation into multiple target instructions.
- **Machine Targets** own **ABI Policy**; **MachV** does not encode host instructions, physical registers, calling conventions, or target constraints.
- Wasmoon JIT owns its **Internal ABI Contract**; each machine target validates and realizes it as a **Target ABI Convention**, while the target alone owns platform convention rules and ABI planning.
- The **Wasmoon JIT ABI Contract** is the single cross-language fact source for Wasmoon native compilation and installation; MoonBit and native glue derive or statically prove the same constants, while the **Wasmoon Runtime** owns only conforming runtime instances and semantic state.
- An **Internal ABI Contract** may request **Persistent ABI Roles** for execution-environment, cache, or return-area values; targets validate them, Target VCode precolors them on demand, and frame planning preserves them.
- After register allocation, each target derives one **Frame Layout** and uses it during emission to generate prologues, epilogues, stack addressing, and unwind frame facts.
- The **Frame Layout Verifier** checks the complete VCode, Allocation, and Frame Layout triple both after planning and before emission writes bytes.
- A **Target ABI Convention** derives a **Call Layout** containing exact argument, result, hidden return-area, stack, fixed-register, and clobber facts; target lowering materializes it without exposing placement orchestration to callers.
- MachV multi-results remain logical SSA values; a **Call Layout** may transfer overflow results through a caller-owned **Return Area**, whose physical offset is chosen only during target frame layout.
- Stack arguments enter Target VCode as symbolic **Incoming Argument Slots** and caller-owned **Outgoing Call Areas**; MachV contains no ABI stack-adjustment, outgoing-store, or stack-base operations.
- Target VCode call allocation facts use fixed or tied operands, explicit timing, and caller-saved clobber ranges; target call instructions do not duplicate argument counts, result classes, or clobber categories.
- **Target VCode** shares function, block, control-flow, virtual-register, and allocation structure without sharing target instructions.
- **Target VCode SSA** remains intact until register allocation returns edge parallel-move edits; target constraints use fixed or tied operands rather than redefining virtual values.
- A **Target VCode Verifier** presents one target-owned checkpoint while privately composing shared structure checks with exhaustive target legality and encoding coverage.
- A **Portable Execution Target** may consume **MachV** without turning **MachV** itself into a stable bytecode or VM contract.
- **Register Allocation** runs after **MachV Target Lowering** and before a **Target Emitter**.
- **MachV** values have no locations; **Allocated Location**, spill slots, ABI areas, and stack-pointer operations begin after **MachV Target Lowering**.
- A **Target Emitter** produces generic relocation and metadata records; **Wasmoon JIT** resolves those records to Wasmoon runtime helpers and executable memory.
- A **Target Emitter** builds bytes, relocations, pools, labels, and metadata in private storage and returns them only after the **Code Object Verifier** accepts the complete unlinked artifact; partial output and reachable emitter aborts are forbidden.
- Each public native compiler stage deterministically returns its first structured failure; **Wasmoon JIT** preserves that typed cause as a **JIT Pipeline Error**, while cancellation remains a separate outcome and human-readable rendering belongs at the presentation boundary.
- Live JIT compilation and **Cwasm Artifact** loading converge at the **Unlinked Code Object** seam; persisted artifacts contain symbolic fixups and Wasmoon metadata but no MilkIR, MachV, Target VCode, resolved process address, or linked image.
- A **Cwasm Artifact** is usable only when its **Artifact Compatibility Manifest** exactly matches the current runtime and request, except that the host CPU features may be a superset; cache mismatch recompiles, while explicit incompatible-artifact loading returns a structured failure.
- The **Wasmoon JIT Compiler** owns one explicit target choice and the complete production compilation sequence; it supplies canonical Wasmoon ABI facts internally, branches to a static machine pipeline once, and owns neither Wasm validation nor runtime linking and installation.
- One **Wasmoon JIT Compiler** may start many **Module Compilations**; each module context compiles functions independently, and lazy, tiered, eager, and Cwasm paths differ only in which function objects they request and aggregate.
- **JIT Code Installation** resolves all symbols before allocation, performs patching and metadata registration before publication, commits function-table visibility last, and returns **Installed Code**; failure leaves the prior visible module unchanged.
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
- Runtime symbol ownership was previously mixed into compiler infrastructure; resolved: reusable layers preserve opaque **External Symbol Identities** and generic relocations, while Wasmoon JIT owns helper names, addresses, and Cwasm mappings.
- Call behavior was previously entangled with ABI and callee categories; resolved: canonical **Call Behavior Summaries** independently describe effects, traps, unwind, and safepoints.
- Trap ownership was previously unclear; resolved: **MachV** owns structured **Semantic Trap** reasons and operation-level trap conditions, while conditional trap fusion and target trap encoding belong to **Target VCode**.
- Scalar-operation ownership was previously unclear; resolved: **MachV** owns precisely typed arithmetic and conversion meaning, while condition flags, fixed registers, shifted operands, and immediate encodings belong to **Target VCode**.
- Vector-operation ownership was previously unclear; resolved: **MachV** currently owns only target-neutral `V128` meaning, while target SIMD forms and wider or scalable vectors remain outside the contract.
- SSA destruction ownership was previously unclear; resolved: **MachV** retains single-definition virtual registers and block parameters, while target-specific constraints and copy insertion begin in **Target VCode**.
- Target VCode's pre-allocation SSA state was previously open; resolved: Target VCode also remains strict SSA, and regalloc alone represents SSA destruction through separate allocation edits.
- Target VCode verification ownership was previously split across generic matches and emitter aborts; resolved: one static **Target VCode Verifier** owns both shared structure and target legality before allocation or emission.
- Portable execution ownership was previously unclear; resolved: **MachV** remains a compiler intermediate representation, while any production bytecode and interpreter belong to a separate **Portable Execution Target**.
- Target packaging was ambiguous; resolved: use ISA-specific modules such as `x64_target` and `aarch64_target`, not generic `backend` or `isa_backend` packages.
- ABI ownership was previously mixed into the machine layer; resolved: **Machine Targets** own **ABI Policy** and apply it after **MachV**.
- Internal and platform ABI ownership was previously conflated; resolved: Wasmoon owns its cross-language **Internal ABI Contract**, while machine targets own validation, platform rules, and concrete **Target ABI Conventions**.
- Runtime register roles previously leaked into MachV; resolved: semantic values remain ordinary MachV SSA, while target lowering introduces on-demand precolored **Persistent ABI Roles** backed only by validated callee-saved registers.
- Frame state was previously accumulated in MachV and emission helpers; resolved: target-owned post-regalloc **Frame Layout** is the sole source for physical stack placement and prologue or epilogue generation.
- Frame correctness was previously guarded by emitter assertions; resolved: a structured **Frame Layout Verifier** proves ownership, placement, ABI, tail-call, GC, unwind, and encoding invariants before byte emission.
- ABI rules and per-call placement were previously represented by one layout object; resolved: a reusable **Target ABI Convention** privately derives a short-lived **Call Layout** for each logical signature.
- Multi-result placement was previously mixed into MachV call opcodes and result classes; resolved: MachV preserves ordered logical results, while target lowering assigns registers or a typed caller-owned **Return Area**.
- Stack argument placement was previously materialized in MachV; resolved: target lowering owns symbolic incoming slots and one reusable outgoing area, while frame layout chooses physical offsets.
- Call allocation facts were previously duplicated between target opcodes and register operands; resolved: compact operand and clobber side tables are authoritative, and regalloc satisfies their fixed constraints.
- Register-allocation placement was reopened; resolved: **Register Allocation** consumes the target-specific representation produced by **MachV Target Lowering**, never **MachV** itself.
- Target-lowering output atomicity was unclear; resolved: success returns complete, verified, target-owned **Target VCode**, while failure returns a structured error without exposing partial builder state.
- Target-lowering context ownership was unclear; resolved: each target consumes its own immutable facts through static specialization, while runtime and downstream compiler services remain outside the lowering seam.
- Target-lowering traversal ownership was unclear; resolved: each target controls its complete lowering and optimization traversal, while the shared layer owns only Target VCode storage and invariants.
- Target-lowering failure ownership was unclear; resolved: each target owns a closed structured error type, and Wasmoon JIT maps it into a product pipeline error only at orchestration.
- Target-lowering dispatch was unclear; resolved: use separate static target entry points and a single orchestration branch, not a runtime target union or dynamic target-lowering interface.
- Target-lowering input ownership was unclear; resolved: borrow verified MachV read-only without cloning, build independent Target VCode privately, and require revalidation after later output mutation rather than introducing a frozen wrapper.
- Regalloc projection was previously modeled as a target-instruction trait returning operand arrays; resolved: lowering records compact allocation facts in the shared Target VCode shell once, avoiding target opcode inspection, repeated projection, and hot-path allocation.
- Post-regalloc representation was unclear; resolved: keep Target VCode virtual and unchanged, return a separate dense allocation keyed by stable handles, and avoid rewriting or copying target instructions.
- Allocation freshness was previously implicit; resolved: owner-scoped stable identities and a complete structural bijection detect stale or cross-function results without persistent verification state.
- Allocation checking was previously split between adapter assumptions and aborting checker paths; resolved: one structured **Allocation Verifier** composes generic correctness with target machine-environment legality.
- Target-lowering metadata ownership was unclear; resolved: preserve target-neutral observable metadata in Target VCode, map safepoint values through allocation, and leave physical encoding and runtime resolution downstream.
- Pipeline validation ownership was unclear; resolved: each public transformation validates both input and output through representation-owned **Verification Checkpoints**, with no caller-managed or disabled safe path.
- Value-location ownership was previously mixed into **MachV**; resolved: MachV safepoints and operations reference values, while **Allocated Location** and frame layout belong downstream.
- Function signatures previously carried ABI result locations, stack counts, and placement facts; resolved: a **MachV Signature** contains only ordered parameter and result types, while ABI facts belong downstream.
- Execution context and return-area parameters were previously both treated as hidden ABI state; resolved: a required execution environment is an explicit logical `Ptr64` value, while a native return-area pointer is introduced only by ABI lowering.
- Call ABI selection was previously inferred from call opcode or clobber class; resolved: function entries and calls carry an explicit finite **Call Protocol** without physical layout or runtime registry lookup.
- Tail calls previously mixed stack byte counts with semantic termination; resolved: MachV preserves a strict **True Tail Call**, while target lowering proves ABI compatibility and rejects layouts it cannot implement without stack growth.
- Conditional and multi-way branches previously carried only target ids, forcing producers to insert jump-only blocks for SSA arguments; resolved: every successor is a **MachV Edge** with explicit arguments.
- Reachability and layout were previously conflated; resolved: a verified **MachV Control-Flow Graph** is rooted and fully reachable, while physical block layout is selected downstream.
- Block identity previously used public integer ids and independently mutable block objects; resolved: a **MachV Block** is an opaque function-owned handle backed by the function's canonical dense block table.
- Instructions previously existed as independently mutable records whose identity was their array position; resolved: a **MachV Instruction** is an opaque function-owned handle backed by canonical instruction data and unique block membership.
- SSA validity previously depended on partial register-id and block-order checks; resolved: **MachV SSA** requires one canonical definition per value and dominance at every instruction, edge, and terminator use.
- Effect order previously depended on scattered opcode knowledge; resolved: **MachV Program Order** plus canonical operation summaries defines observable ordering without introducing effect-token values.
- Terminators previously mixed semantic control flow with AArch64 and AMD64 branch forms; resolved: **MachV Terminator** has one minimal target-neutral vocabulary, while encoded branch selection belongs downstream.
- Mutation safety previously depended on callers repairing directly mutable arrays; resolved: the **MachV Mutation Boundary** is locally atomic, while explicit verifier checkpoints validate cross-entity invariants.
- Verification previously mixed partial SSA checks with target register policy; resolved: the **MachV Verifier** validates only the complete target-neutral MachV contract, while target representations have their own verifiers.
- Native compilation failures were previously vulnerable to aborts or string flattening; resolved: stage-owned structured errors cross Wasmoon orchestration as **JIT Pipeline Errors**, while cancellation remains a distinct outcome.
- Machine-code-emission ownership was previously unclear; resolved: target emitters privately build and verify complete unlinked code objects, while **Wasmoon JIT** owns relocation resolution, linking, and executable-memory installation.
- Precompiled output ownership was ambiguous; resolved: **Cwasm Artifact** belongs to **Wasmoon JIT** and persists only **Unlinked Code Objects** plus product metadata, never compiler IR or process-specific linked state.
- Artifact compatibility was previously inferred from a format version and target architecture; resolved: a strict **Artifact Compatibility Manifest** covers every code, ABI, runtime, source-semantics, and compilation-policy dimension needed for safe reuse.
- Production compilation orchestration was previously spread across callers and `EmitTarget` parameters; resolved: one deep **Wasmoon JIT Compiler** owns target selection and the mandatory pipeline through unlinked emission without absorbing frontend or installation responsibilities.
- Live, tiered, eager, and Cwasm compilation previously risked becoming separate pipelines; resolved: an immutable **Module Compilation** exposes one function-granular compilation primitive and treats module compilation as aggregation.
- Code installation previously exposed function pointers before all fixups and runtime metadata were ready; resolved: **JIT Code Installation** is one rollback-safe transaction whose final action publishes the complete **Installed Code**.
- VMContext layout, runtime symbols, trap codes, and stack maps previously had multiple handwritten owners; resolved: one versioned **Wasmoon JIT ABI Contract** owns their cross-language representation, while runtime instances, installer actions, and platform primitives retain separate lifecycle responsibilities.
- Native JIT glue ownership was ambiguous; resolved: **JIT FFI** remains in **Wasmoon JIT** for the first split instead of creating a generic executable-memory module.
- "Wasmoon Runtime" names an execution-system concept, not a required package named `wasmoon_runtime`; resolved: keep the package name decision separate from the concept.
