# Wasmoon Compiler Infrastructure

This document defines the current language and ownership boundaries of the
Wasmoon compiler. Terms describe real representations or protocols in the
repository; speculative targets do not receive placeholder abstractions.

## Language

**Wasm Core**:
The reusable WebAssembly specification model shared by parsers, validators,
frontends, and runtimes.

**Wasm Frontend**:
The Wasmoon-owned translation from validated WebAssembly into MilkIR.

**Embedding Environment**:
The runtime-provided interface that maps opaque context fields, functions, and
helpers to symbolic native identities without exposing VMContext layout to
reusable compiler modules.

**MilkIR**:
The sole target-independent whole-function compiler IR. It owns SSA values,
blocks, control flow, operations, verification, and optimization.

**MilkIR Dialect**:
A validated extension vocabulary owned by a source domain. `wasm_milkir` owns
WebAssembly-specific operations that cannot yet be expressed as core MilkIR.

**Native Value Type**:
One of `I32`, `I64`, `F32`, `F64`, `V128`, `Ptr64`, or `GcRef64`. The type
preserves exact carrier meaning without selecting a register bank or location.

**Native Lowering Stream**:
A transient sequence of typed operations and terminators sent from MilkIR to
one target sink. It has opaque short-lived value and block handles but owns no
function graph, CFG, SSA table, or instruction storage.

**Target Sink**:
The callback protocol implemented by a concrete target lowering session. It
creates target blocks and stack-object requests, selects each streamed
operation, receives terminators, and seals the resulting Target VCode.

**Direct Builder**:
The producer-side coordinator for a Native Lowering Stream. It maps MilkIR
entities to opaque stream handles, elaborates shared call ABI requirements,
and forwards each operation exactly once.

**Dialect Lowering Adapter**:
A validator and translator for one MilkIR dialect. It may resolve embedding
capabilities and emit ordinary native operations through the Direct Builder,
but it cannot observe or mutate target VCode.

**Native Call**:
A target-independent call description containing symbolic callee identity,
logical signature, call protocol, and behavior. Targets own argument/result
placement, clobbers, and instruction expansion.

**Call Protocol**:
The explicit choice between an embedding-defined internal convention and the
host platform convention. Protocol is independent of direct, indirect, or
external callee identity.

**Environment Field**:
A typed symbolic field supplied by the embedding. A target lowering context
resolves it to a path of byte offsets when selecting native loads.

**Stack Object Request**:
A target-independent identifier, size, and alignment created during streaming
lowering. Physical frame offsets do not exist until target frame planning.

**Target VCode**:
The target-owned virtual-register machine representation parameterized by one
ISA instruction type. It owns target instructions, block layout, constraints,
fixed-register uses, symbolic ABI areas, and allocation side tables.

**Selected Function**:
An opaque target-owned result produced after Target VCode construction and
target validation succeed. Failed lowering exposes no partial function.

**Register Allocation**:
The reusable algorithm that observes Target VCode through a read-only
`FunctionView` and returns a verified allocation plan. It does not own or copy
a second instruction graph.

**Allocated VCode**:
Target VCode plus a materialized mapping from virtual values to physical
registers or spill slots. The mapping is independently verified before frame
planning.

**Transfer Scratch**:
One reserved register per register bank used only to linearize parallel moves.
It is distinct from spill/edit and instruction-emitter scratch roles.

**Emergency Move Area**:
An optional raw 16-byte frame area used when a parallel-move cycle must
temporarily preserve the live transfer scratch. Frames that do not need it pay
no space cost.

**Frame Layout**:
The target-owned post-allocation placement of spills, stack objects, incoming
and outgoing arguments, return areas, callee saves, and emergency move data.

**Unlinked Code Object**:
Verified ordinary data containing machine bytes and symbolic relocations,
traps, safepoints, source locations, roots, and unwind directives. It contains
no process addresses or executable-memory ownership.

**Wasmoon JIT Integration**:
The product-owned layer that supplies VMContext layout, runtime helper symbols,
artifact compatibility, executable-memory installation, trampolines, fibers,
trap transport, and GC integration.

## Ownership Rules

- `wasm_core` does not depend on MilkIR, native compilation, or Wasmoon runtime
  packages.
- MilkIR is the only target-independent retained program graph in native
  compilation.
- `native_types`, `native_lowering`, `milkir_native`, `wasm_native`, `vcode`,
  `regalloc`, `vcode_regalloc`, and both target modules are reusable and do not
  import Wasmoon-owned packages.
- A Native Lowering Stream is consumed once. It is not printable, optimizable,
  serializable, or exposed as a compatibility representation.
- A target session explicitly maps transient stream handles to target-owned
  block and value identities; numeric equality between those domains is never
  assumed.
- WebAssembly dialect validation occurs before the target accepts the related
  operation. Unknown or ill-typed extensions fail with a structured error.
- Calls, traps, memory effects, safepoints, live GC roots, and source locations
  remain explicit across direct lowering.
- Shared call ABI elaboration may insert root-scope operations and hidden stack
  maps, but concrete argument placement remains target-owned.
- Every successful target lowering produces complete, verified Target VCode.
  Placeholder instructions used to preserve construction after an error can
  never escape a failed session.
- Register allocation operates on target constraints and target register
  classes. No target-independent layer assigns physical locations.
- Scratch roles are disjoint and verified: transfer scratch, spill/edit
  scratch, fixed-operand scratch, and emitter-local scratch are not
  interchangeable.
- Stack-object offsets, spill offsets, outgoing areas, prologues, and epilogues
  are derived only by target frame planning.
- External symbols remain symbolic until Wasmoon JIT installation.
- A future portable interpreter is a separate executable target with its own
  instruction semantics. It is added only when a real consumer requires it.

## Native Pipeline

```text
validated Wasm
  -> Wasm frontend
  -> MilkIR
  -> MilkIR optimization
  -> streaming core and Wasm-dialect native lowering
  -> AArch64 or x64 Target VCode
  -> VCode register allocation
  -> target frame planning and emission
  -> Unlinked Code Object
  -> Wasmoon artifact and JIT installation
```

The interpreter consumes validated WebAssembly runtime structures separately;
it does not execute a compiler intermediate representation.
