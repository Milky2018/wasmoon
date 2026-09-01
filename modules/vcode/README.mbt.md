# vcode

`Milky2018/vcode` provides the target-independent infrastructure shared by
Wasmoon's native backends. It defines the semantic vocabulary at the native
compiler boundary, a streaming instruction-selection protocol, dense storage
for target-owned VCode, allocation side tables and verifiers, parallel-move
planning, and verified unlinked code objects.

The module is intended for compiler backends and embedding runtimes. It is not
a source-language IR, an optimizer, a register allocator, or an executable-code
loader. MilkIR owns target-independent program structure and optimization;
`Milky2018/regalloc` owns allocation policy; each target owns its instructions,
ABI, frame layout, and encoding; the embedding product owns symbol resolution,
executable memory, and runtime registration.

## Packages

| Package | Responsibility |
| --- | --- |
| `Milky2018/vcode/native_types` | Canonical native value types, signatures, calls, symbols, operation effects, traps, safepoints, source locations, and stack-map metadata. |
| `Milky2018/vcode/native_lowering` | Streaming producer-to-target protocol, target-neutral operations, transient value and block handles, and call-ABI elaboration. |
| `Milky2018/vcode/allocation_types` | Minimal register-allocation vocabulary shared by VCode, the allocator, and their adapter: register classes, physical and virtual registers, operand roles and timing, constraints, and compact locations. |
| `Milky2018/vcode` | Dense target VCode, checked construction, allocation and frame side tables, staged verification, call-transfer planning, and parallel-move resolution. |
| `Milky2018/vcode/code_object` | Verified machine-code bytes with typed relocations, source and trap sites, safepoints and roots, and target-neutral unwind directives. |

These packages are separate ownership seams inside one module, not successive
copies of the same IR. In particular, `native_lowering` does not depend on the
VCode package and does not retain a function graph. A target implements a
`TargetSink` that translates each streamed operation directly into its own
instruction type stored by `vcode`.

## Compiler flow

```text
MilkIR and dialect adapters
          |
          | native_lowering.Operation, one operation at a time
          v
target TargetSink --> target-owned Inst in vcode.Function[Inst]
                                      |
                                      | verify_selected
                                      v
                      regalloc + vcode allocation side tables
                                      |
                                      | verify_allocated
                                      v
                              target frame layout
                                      |
                                      | verify_framed / verify_emission_input
                                      v
                              target machine-code emitter
                                      |
                                      v
                         code_object.UnlinkedCodeObject
                                      |
                                      v
                       embedding-owned linker and code loader
```

`native_types` supplies the common vocabulary on both sides of the lowering
seam. `allocation_types` supplies identities that must be shared exactly by
VCode and `Milky2018/regalloc`; targets should not introduce parallel register
class, operand-role, or allocation-location types.

## Constructing target VCode

The instruction payload is generic. A target defines an instruction type, then
uses `CheckedBuilder[Inst]` to attach operands, constraints, clobbers, CFG
edges, and metadata. Handles are function-owned, so values, blocks, and
instructions from different functions cannot be mixed accidentally.

```moonbit check
///|
priv enum ExampleInst {
  AddOne
  Return
} derive(Debug)

///|
test "construct and verify target VCode" {
  let builder : CheckedBuilder[ExampleInst] = CheckedBuilder::new_with_results(
    "add_one",
    [I64],
    [I64],
  )
  let entry = builder.entry_block()
  let input = builder.parameter(0)
  let (_, results) = builder.append_body(
    entry,
    AddOne,
    [Input::any(input)],
    [Output::any(I64)],
    [],
    InstructionMetadata::empty(),
  )
  builder.set_terminator(
    entry,
    Return,
    [Input::any(results[0])],
    [],
    [],
    InstructionMetadata::empty(),
  )
  |> ignore

  let function = builder.finish()
  verify_selected(function)
  inspect(function.parameter_count(), content="1")
  inspect(function.instruction_count(), content="2")
  inspect(function.summary().contains("AddOne"), content="true")
}
```

`CheckedBuilder` is the normal production construction API: it rejects invalid
operands and edges before mutation and checks local completeness when it is
sealed. It does not replace `verify_selected`, which checks whole-function CFG
and SSA properties. The lower-level `Builder` is useful for negative tests and
tooling that deliberately needs to construct an invalid intermediate state.

An `Input` or `Output` describes a correctness constraint independently from a
placement preference. `Fixed` and `TiedTo` are hard constraints. A preferred
physical register is only a hint and must not make an otherwise legal
allocation fail. `Early` and `Late` operand timing lets the allocator model
when an instruction stops using an input and starts defining an output.

## Streaming native lowering

`Milky2018/vcode/native_lowering` is the boundary between a legalized MilkIR
producer and a native target. `DirectBuilder` exposes typed, transient `Value`
and `Block` handles to the producer and forwards operations to a `TargetSink`.
It retains only the bookkeeping needed to track types, map transient handles to
target ids, delay one terminator, and elaborate configured call ABI details.
It does not retain instructions, uses, SSA definitions, or CFG edges.

The protocol defines operation semantics, while the producer owns source-level
legalization. The target owns instruction selection, target immediates,
calling-convention decisions, physical-register policy, and target VCode
verification. Call-ABI elaboration may add hidden stack-map arguments or caller
root scopes, but only when an embedding explicitly supplies the corresponding
contract.

Use `Milky2018/milkir/native` to stream core MilkIR and
`Milky2018/wasm_milkir/native` for the WebAssembly dialect. Target users normally
create an AArch64 or x64 lowering session instead of constructing a
`TargetSink` directly.

## Allocation and move planning

`Function[Inst]` is the authoritative selected machine graph. Allocation is
stored separately in `Allocation`, so register assignment, spills, reloads,
edge transfers, safepoint roots, and frame placement do not rewrite or clone
the instruction graph. `Milky2018/vcode_regalloc` exposes the function through
the allocator's read-only view and materializes its returned plan into these
side tables.

Parallel assignments are planned with a dedicated transfer scratch for each
register bank. When a cycle and a stack-to-stack transfer cannot be resolved
safely with that scratch, the planner emits explicit emergency save and restore
steps. The target owns the physical emergency area and must verify that its
frame reserves it whenever the resolved plan requires it.

The verification functions represent lifecycle boundaries:

- `verify_selected` checks CFG shape, SSA dominance, operands, clobbers,
  metadata, and layout before allocation.
- `verify_allocated` checks homes, operand locations, edits, interference,
  clobbers, and safepoint roots after allocation.
- `verify_framed` adds spill-slot placement, alignment, overlap, and frame-size
  checks.
- `verify_emission_input` is the final target-independent gate immediately
  before encoding.

Verification validates the current snapshot; it does not permanently mark a
mutable function or side table as verified. Run the appropriate verifier again
after any later mutation.

## Unlinked code objects

`Milky2018/vcode/code_object.build` is the final reusable boundary between a
target emitter and an embedding runtime. It copies the machine-code bytes and
metadata, validates them, and returns an `UnlinkedCodeObject` only when all
architecture, alignment, bounds, relocation, instruction-encoding, stack-map,
root-location, and unwind-state contracts hold.

```moonbit nocheck
///|
let object = @code_object.build(@code_object.X64, [b'\xc3'])
```

Relocations remain symbolic. The package does not resolve runtime symbols,
apply relocations, allocate executable memory, encode platform unwind formats,
or register unwind data with the host. Those responsibilities belong to the
embedding runtime. An unwind directive's offset is the code offset immediately
after the prologue instruction that establishes the described state; saved
register locations are relative to the canonical frame address.

## Integration guidance

- Import the narrowest package that owns the contract you need. A frontend
  usually needs `native_types` and `native_lowering`; a target also needs the
  root package and `code_object`; a loader normally needs only `native_types`
  and `code_object`.
- Keep target-specific instruction variants and ABI policy in the target
  module. The generic packages should never depend on AArch64, x64, or Wasmoon
  runtime layouts.
- Keep runtime symbol resolution and executable-code installation outside this
  module. Code objects are ordinary verified data until an embedding installs
  them.
- Treat verification errors as compiler contract failures with structured
  diagnostics. Do not bypass a failed stage to continue emission.
