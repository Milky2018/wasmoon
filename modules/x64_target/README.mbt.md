# x64_target

x64 backend for direct MilkIR instruction selection.

This module owns x64 instruction selection, validation and lowering of an
embedding-provided internal ABI contract, register allocation policy, frame
layout, machine-code emission, relocations, and final linking. A
`DirectLoweringSession` consumes the streaming native-lowering protocol and
constructs verified x64 Target VCode without an intermediate function graph.

## Package

- `Milky2018/x64_target`: x64 Target VCode, lowering, allocation, frame layout,
  emission, and linking.

## When to use it

Use this module as the target sink for `Milky2018/milkir/native`, then install
its generated code object through the embedding runtime.

## Example: define the internal ABI

```moonbit check
///|
test "validate the x64 internal ABI" {
  InternalAbi::new(7, 10, [6, 2, 1, 8, 9], [0, 1, 2, 3, 4, 5, 6, 7], [0, 2], [
    0, 1,
  ])
  |> ignore
}
```

## Integration

Finish a `DirectLoweringSession`, then use `compile_selected` for the aggregate
path, or call `allocate`, `plan_frame`, and `emit` when inspecting checkpoints.
The returned `UnlinkedCodeObject` contains bytes, relocations, and safepoints;
the embedding application supplies symbol addresses and executable memory.

`compile` accepts an optional `on_event` callback that reports generic stage
boundaries and a read-only allocation summary. This lets an embedding collect
metrics without coupling the target to a product metrics system. The callback
must not mutate compiler inputs.

Parallel moves use R15 and XMM13 as dedicated transfer scratches and share the
target-neutral emergency-aware move planner with AArch64. R10 and XMM14 remain
the allocator's spill/edit scratches; R11 is a declared fixed-operand-only
instruction temporary, and XMM15 remains reserved for emitter-local expansion.
The frame reserves a raw 16-byte emergency area only for move groups that
require it.
