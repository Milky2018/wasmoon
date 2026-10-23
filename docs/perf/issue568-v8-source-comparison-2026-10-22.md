# Issue 568: V8 source comparison for the decimal shift loops

This is source research, not a new optimization or a performance attribution.
No production code was changed. The parent investigation owns measurements and
the actual three-engine IR/disassembly comparison. In particular, the source
differences below do not assign a percentage of the remaining wall-time gap.

## Revision and binary contract

The installed executable is `/opt/homebrew/bin/node` (Homebrew Node 25.2.1,
ARM64). `process.versions.v8` reports `14.1.146.11-node.14`.
`process.config.variables` reports `v8_enable_pointer_compression=0`,
`v8_enable_pointer_compression_shared_cage=0`, and `v8_enable_sandbox=0`.
Consequently, compressed 32-bit references are **not** an explanation of this
binary's advantage. There is no installed `d8` shell.

The official annotated Node tag `v25.2.1` resolves to Node commit
[`4cac2b94bed4bf02810be054e8f63c0048c66564`](https://github.com/nodejs/node/commit/4cac2b94bed4bf02810be054e8f63c0048c66564).
All V8 links below refer to its vendored `deps/v8`, rather than the different
`ce9b6028` V8-main snapshot used in earlier research. This is the matching
released source baseline; the Homebrew binary was not independently rebuilt,
so build flags were checked from the actual executable instead of inferred.

The Wasmoon source comparison is against
`c7e407d5686a21dde271a240ca6f5b9a8f20352e`. The guest is the existing Core
property artifact: seed 37, 20,000 properties, six spellings, with assertions
retained. Its `Decimal.left_shift` and `Decimal.right_shift` loops operate on
packed-byte digits; the left shift also divides an Int64 accumulator by the
constant 10 for each digit. The exact artifact hash and function-index mapping
belong to the parent measurement receipt.

## Concrete source chain

### 1. Validated Wasm becomes typed GC operations before ordinary memory IR

`TurboshaftGraphBuildingInterface::StructGet/StructSet` constructs typed
operations with the actual `StructType`, module type index, field index,
signedness and a nullable/non-nullable check obligation. `ArrayGet/ArraySet`
first call `BoundsCheckArray`, then construct the access operation.
`BoundsCheckArray` uses `ArrayLength` plus an unsigned `index < length` test;
the normal path retains the out-of-bounds trap. This is not a scheme that
trusts a guessed array width or removes checks globally.
[Struct entry](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/wasm/turboshaft-graph-interface.cc#L4588-L4629),
[array entry](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/wasm/turboshaft-graph-interface.cc#L4760-L4796),
[bounds construction](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/wasm/turboshaft-graph-interface.cc#L8419-L8455).

`ArrayGetOp` explicitly cannot trap because the preceding length check owns
that obligation. It carries a tagged object input and Word32 index, and
depends on protective checks. Struct operations retain a trap effect when
nullable; mutable reads, writes and atomic ordering have distinct effects.
The distinction matters: load forwarding, trap movement and GC pointer
lifetime are separate questions.
[Operation contracts](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/operations.h#L7207-L7510).

For host input, `JSToWasmObject` checks nullability, object category and
canonical subtyping. A Wasm struct/array's map supplies its canonical actual
type, which must be a subtype of the expected type. This is an explicit
boundary contract, not a type check repeated by every numeric field load.
This function demonstrates the checked conversion contract; it does not mean
every wrapper executes this exact C++ function on its fast path.
[Host conversion](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/wasm/wasm-objects.cc#L3456-L3490),
[canonical indexed types](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/wasm/wasm-objects.cc#L3611-L3683).

### 2. Type, alias and loop analysis happen while operations are still typed

The pipeline constructs the Turboshaft graph, optionally peels/unrolls loops,
runs `WasmGCOptimizePhase`, then `WasmLoweringPhase`, then
`WasmOptimizePhase`. The GC phase composes load elimination and typed GC
optimization. The later phase composes escape analysis, machine optimization,
allocation optimization, branch elimination, late load elimination and value
numbering. Those phases can optimize ordinary loads after GC lowering.
[Pipeline](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/pipeline.cc#L3144-L3213),
[GC phase](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-gc-optimize-phase.cc#L15-L20),
[late phase](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-optimize-phase.cc#L22-L29).

The GC load-elimination table keys struct fields by base identity, physical
field offset, module type index, size and mutability. Writes invalidate
possibly aliasing entries at that field, using type unrelatedness and fresh
non-aliasing objects; a field write can also supply the next read's value.
Array length is a separate immutable load-like fact. Loop snapshots are
revisited to reach stable state. This is broader than recognizing a particular
`StructGet` producer in a loop preheader.
[Keys and invalidation](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-load-elimination-reducer.h#L51-L202),
[loop iteration](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-load-elimination-reducer.h#L415-L459),
[field and length forwarding](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-load-elimination-reducer.h#L762-L837).

Important limit: the high-level GC load-elimination pass explicitly does **not**
eliminate array element loads. `ArraySet` therefore does not clear struct
field facts. Generic late load elimination is a later opportunity after the
array accesses have become ordinary memory operations. It would be inaccurate
to describe V8 as having one all-powerful GC array LICM pass.
[Explicit array limitation](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-load-elimination-reducer.h#L612-L647).

Calls without a write effect preserve the GC load facts. Writing calls revoke
freshness of their arguments and invalidate potentially aliasing memory.
Typed GC analysis separately removes null checks only after its inferred
input type is non-null. A safepoint is not automatically a write to every
logical object field; a raw interior pointer nevertheless has stricter
lifetime constraints than a traced tagged reference.
[Call invalidation](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-load-elimination-reducer.h#L888-L921),
[null-check reduction](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-gc-typed-optimization-reducer.h#L344-L417).

### 3. GC lowering generates direct typed accesses, not field helpers

`WasmLoweringReducer::StructGet` obtains the field offset from the validated
layout, selects the correct signed/unsigned memory representation, and emits
`Load(object, ..., field_offset)`. Immutable fields are marked immutable.
The nullable case uses an explicit null branch or a trap-on-null load as
appropriate. `StructSet` emits a `Store`; numeric fields have no write barrier,
reference fields request a full barrier.
[Struct lowering](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-lowering-reducer.h#L237-L312).

`ArrayGet/ArraySet` emit a tagged-base load/store with
`WasmArray::kHeaderSize` and the static element-size shift. The length load is
immutable. There is no stable object-number lookup, per-element descriptor
lookup or generic C ABI call in that numeric fast path. Reference element
stores retain their write barrier.
[Array lowering](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-lowering-reducer.h#L351-L423).

The ARM64 selector maps Uint8 to LDRB, Int8 to LDRSB, integer widths to LDR,
floating widths to their corresponding scalar loads, and ordinary tagged
references to a 64-bit LDR when pointer compression is disabled. Protected
null accesses retain trap metadata; reference stores use an explicit
write-barrier selection path. These are source-level code-selection facts;
the exact register assignments and eliminated checks for the property must
come from the actual function's disassembly.
[Loads](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/backend/arm64/instruction-selector-arm64.cc#L1142-L1234),
[barrier stores](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/backend/arm64/instruction-selector-arm64.cc#L1241-L1290).

### 4. A concrete arithmetic difference must not be mistaken for GC cost

`Decimal.left_shift` divides its Int64 accumulator by 10 for each digit.
V8's `ReduceSignedDiv` handles constant divisors with signed magic-number
division: high-half multiply, optional addition, arithmetic shift and sign
correction. Wasmoon's current ARM64 direct lowering instead emits checked
SDIV for generic signed division; its existing strength reduction handles
unsigned powers of two. The exact left-shift machine code must confirm
whether this survives, but the source establishes a non-GC optimization gap.
Neither extra instructions nor SDIV latency should be attributed to GC helper
overhead without that check.
[V8 constant division](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/machine-optimization-reducer.h#L2637-L2698),
[Wasmoon checked division](../../modules/aarch64_target/direct_lower.mbt),
[Wasmoon strength reduction](../../modules/milkir/optimize/loops.mbt).

### 5. Allocation, references and tracing are one runtime/compiler contract

The GC representation in this Node build is an ordinary tagged V8 heap-object
reference. Wasm objects inherit `JSReceiver`; arrays add a UInt32 length and
padding on the eight-byte tagged configuration. Struct fields are laid out
using their actual widths and alignment, and arrays occupy header plus rounded
`element_size * length`. This does not require one 16-byte cell per numeric
field. Wasmoon already has packed physical layouts; copying this fact alone
does not explain its remaining RSS.
[Object definitions](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/wasm/wasm-objects.tq#L295-L306),
[struct layout](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/wasm/struct-types.h#L61-L132),
[array size](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/wasm/wasm-objects-inl.h#L775-L793).

Unshared array allocation lowers to a young-generation `Allocate` plus header
initialization. `MemoryOptimizationReducer` loads allocation top/limit through
the trusted instance data and emits a bump-pointer fast path; exhaustion and
large allocations call the allocation builtin. Allocation folding and
barrier elimination are graph analyses, not promises to elide all allocation
work. Shared objects have a separate shared-heap path.
[GC allocation](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-lowering-reducer.h#L426-L483),
[fast/slow allocation](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/memory-optimization-reducer.h#L237-L415).

Effects explicitly distinguish mutable heap memory, off-heap memory, checks,
allocation and untagged/raw heap access. `CanAllocate` can trigger GC and
requires a consistent heap. `CanDoRawHeapAccess` creates ordering constraints
against operations requiring consistency. This is a concrete basis for
separating object-value facts from a temporary untagged view's validity.
[Effect contract](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/operations.h#L672-L754).

For transitive tracing, the native `WasmArray::BodyDescriptor` scans elements
only if their layout is reference-valued; the struct descriptor visits only
reference-typed fields using canonical field offsets. Thus object edges are
enumerated by native heap descriptors. This is different from repeatedly
decoding every object through a guest identity/type registry. It does not
prove the parent workload collects enough for tracing to dominate.
[Native object-edge descriptors](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/objects/objects-body-descriptors-inl.h#L1202-L1237).

### 6. Root maps replace normal guest-call root copying, including parked stacks

The register allocator's `ReferenceMapPopulator` selects reference live ranges
covering each safepoint and records their allocated locations. The code
generator records tagged stack slots in the PC-indexed safepoint table.
`WasmFrame::Iterate` looks up code plus safepoint for the saved PC, scans the
specified spill slots, tagged incoming parameters and instance data. There
are still spill costs and wrapper/handle roots; this is not zero-cost rooting.
It avoids Wasmoon's normal guest-call mechanism of copying a root array into
an execution-context scope and pushing/popping that scope through C helpers.
[Allocated reference maps](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/backend/register-allocator.cc#L4770-L4901),
[table generation](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/backend/code-generator.cc#L577-L598),
[Wasm frame scanning](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/execution/frames.cc#L1685-L1847).

Suspension does not make these maps irrelevant. Isolate root iteration visits
each inactive Wasm stack, then the current execution stack. A suspended
`StackMemory::Iterate` constructs a stack-frame iterator over its saved state
and invokes the same per-frame iterators, and also visits continuation roots.
Wasm-to-JS wrapper frame handling is explicit. A Wasmoon stack-map migration
must cover active execution, host reentry, parked stacks, tail calls and
exception unwinding together; deleting scopes before those paths are covered
would revive prior rollback/root-liveness bugs.
[All stacks](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/execution/isolate.cc#L640-L659),
[parked frame traversal](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/wasm/stacks.cc#L102-L112),
[wrapper parameters](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/execution/frames.cc#L1852-L1953).

## What this suggests replacing in Wasmoon

These are design recommendations with explicit prerequisites, not deletion
authorization beyond the user's requested proposal.

| Existing mechanism | Replacement | Prerequisite before removal |
|---|---|---|
| Independent GC-read forwarding, checked-loop hoisting, first-use loop caching, followed by a second native array-view planner | One typed memory/alias/effect analysis, then general value numbering/LICM with explicit check dependencies | Match each existing trap-order, alias, zero-trip and loop regression; expose conservative call summaries and invalidate analyses after CFG edits |
| Producer-specific `StructGet` recognition in `array_view_reference` and preheader backward searches | SSA reference values plus one derived-address operation/effect contract | Preserve temporary view validity across only proven no-GC regions; do not equate a logical reference with an interior pointer |
| Numeric struct C helper calls and repeated ID/layout resolution on trusted guest paths | Direct typed struct loads/stores after a checked representation boundary | Authoritative runtime layout ID/static layout contract, host-result/import/table entry type validation, checked legacy-host fallback |
| Per-normal-guest-call caller-root scope copying | PC-indexed safepoint maps linked to allocated live references | Active/parked/reentrant frame walking; tail/hidden-result ABI; unwinding, cancellation and escaped exception/root regressions on both architectures |
| Generic divide-by-constant lowered as checked hardware division | General integer strength reduction before target lowering | Signed rounding, zero, `MIN / -1`, remainder and 32/64-bit public semantics tests; confirm exact hot-loop assembly first |
| Store-mediated native object-edge traversal when a native descriptor already owns layout | Native descriptor-based edge enumeration | Account for managed/native hybrid references, exception payloads and continuation/external roots; incomplete discovery must remain conservative |

Do **not** delete stable host IDs merely because V8 uses tagged pointers.
Stable handles are an embedding/lifetime contract and decouple host references
from object movement. A dual boundary representation (stable host handles,
traced internal references) is a larger design option, not a free local
rewrite. Likewise, do not import V8 pointer compression, sandbox cages,
JavaScript maps or its whole generational collector as prerequisites for
efficient numeric loads. The current Node comparison does not even use
pointer compression.

A PC-map implementation can initially describe Wasmoon's existing stable-ID
reference words. It need not simultaneously migrate guest references to
moving object pointers: the native tracer can decode mapped ID words, while
separately derived physical addresses expire at safepoints. This separates the
root-registration redesign from the much larger host/reference representation
decision. Conversely, direct static-offset loads need a normalized physical
layout contract; retaining arbitrary wide host cells and silently assuming
packed guest cells is not that contract. Normalize at admission or retain a
deliberate checked boundary fallback until normalization is complete.

The deciding experiment is a per-loop table from the exact same artifact:
remaining helper calls, root operations, bounds/null branches, scalar SDIV vs
SMULH sequences, spills, safepoint positions and instruction counts. Source
reading identifies mechanisms; it cannot by itself say which of those costs
dominates the remaining approximately two-fold wall-time gap.

## Reproducing optimized V8 diagnostics

The installed Node exposes `--no-liftoff`, `--no-wasm-lazy-compilation`,
`--wasm-num-compilation-tasks=1`, `--print-wasm-code`,
`--print-wasm-code-function-index=454`, `--trace-turbo`, and
`--trace-turbo-path`. An optimized-only run and a normal-tiering run should be
reported separately. Instrumented disassembly/IR runs are not timing runs.

The trace filter is matched against the compiler debug name. When tracing or
printing is enabled and the custom name section has a name, V8 uses that
actual name; otherwise it uses `wasm-function#454`. Thus the filter must be
the exact name or `*left_shift*`, not `wasm-function[454]`.
[Name selection](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/wasm-compiler-definitions.cc#L17-L48),
[filter application](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/codegen/optimized-compilation-info.cc#L60-L75).

All downloaded upstream sources were read in an OS `TemporaryDirectory` and
are removed when the research owner exits. No toolchain, dependency, runtime
or compiler code was modified for this research.
