# Wasm native lowering

`Milky2018/wasm_milkir/native` validates WebAssembly-specific MilkIR extensions and
streams target-neutral native operations into an AArch64 or x64 target sink.
It does not own a second function graph, select concrete instructions, or
depend on the Wasmoon runtime.

The embedding environment supplies opaque internal function identities and,
as later operation families are migrated, the semantic runtime capabilities
required by WebAssembly memory, tables, GC, and exceptions.

`lower_to_sink` also requires a short-lived `WasmValidationContext` supplied
by the Wasm frontend adapter. It resolves linked function signatures and
module-local type, table, aggregate, tag, memory, and segment contracts before
instruction selection. The context is not retained by the lowering stream.

## Borrowed numeric-array regions

The embedding can opt into the `GcArrayDataHeap` projection ABI. It returns a
borrowed payload pointer only after checking the live identity, array kind,
actual immutable physical layout, scalar width and absence of reference fields.
The payload has an i32 length at offset zero and elements at offset 16. A null
pointer selects the existing checked accessors. The projection is nontrapping,
including absent heaps and null references. Wide host objects, reference and
v128 arrays, layout mismatches and runtime GC verification keep those accessors.
The compiler does not embed offsets into an embedding's heap/identity/layout
structures. Wasmoon checks the projection ABI's data offset at C compilation.

A compiler-private plan identifies each preparation point and its uses. An
independent verifier runs even when generic input validation was disabled. A
failed proof discards the physical plan. Ordinary regions follow only forward,
single-predecessor CFG edges. Calls (including polls and reentry), allocation,
unknown operations and raw memory writes end them. Joins and backedges start new
regions, except for a separately checked natural-loop proof. An array check or
reference-valued struct read must have executed in its unique preheader, no
later preheader operation may invalidate the view, and every path around the
loop must be free of safepoints and side entries. A produced reference can be
nullable: querying its view does not trap, and each actual array operation
retains the original checked fallback. An untaken or zero-trip loop therefore
acquires no new trap. The query uses the producer's completed result, never the
holder operand; its actual physical layout is still checked by the embedding.

A view contains only the physical payload and immutable length. Element values
are loaded on every access, so writes through aliases remain visible. Numeric
stores need no reference barrier; reference stores retain the existing barrier
implementation. Every element access still performs an unsigned bounds check;
failure takes the original helper and preserves its trap. The native selector
emits ordinary target-neutral load/store operations on successful accesses.
Prepared pointers never become Wasm values or cross a safepoint. The embedding
must not mutate its heap concurrently outside the execution/safepoint protocol.

The planner, proof checker and emitter stay in this package because they use the
same private `Environment`, helper ABI and `InstructionContext`. No Wasmoon
package is imported into the reusable compiler, and no second native IR graph
or public unchecked-pointer operation is introduced.
