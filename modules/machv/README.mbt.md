# machv

MachV provides the target-neutral semantic machine IR and the shared storage
contracts used after target instruction selection.

## Packages

- `Milky2018/machv`: typed target-neutral SSA, builders, cleanup, printing, and
  verification.
- `Milky2018/vcode`: generic dense Target VCode storage parameterized by
  a target-owned instruction type, plus allocation, frame, and final-emission
  input contracts.
- `Milky2018/code_object`: verified, unlinked machine code plus typed
  relocations, traps, safepoints, roots, and unwind bytes.

The VCode package does not define a union of AArch64 and x64 instructions.
Each target supplies its own closed instruction type, while the shared package
stores CFG edges, SSA values, stable instruction handles, operand constraints,
soft physical-register preferences, clobbers, safepoints, and allocation edits.

The VCode package also owns the pure call-transfer planner shared by machine
targets. After allocation, targets normalize ABI register and outgoing-stack
destinations into one atomic transfer request. The planner captures stack
arguments before destructive register moves, resolves register cycles, protects
safepoint root homes, and returns a verified ordered plan. ABI layout, frame
offsets, and instruction encoding remain target-owned.

VCode models AArch64/x64 hardware aliasing directly: scalar floating-point and
SIMD values share one `FpVector` register bank. They can never be allocated to
the same physical register as if the hardware exposed independent banks.

## Pipeline boundary

Target lowering consumes verified semantic MachV and produces a complete
`Function[TargetInst]`. Register allocation reads the compact operand side
tables and returns a separate `Allocation`; it does not rewrite Target VCode.
Frame planning and emission consume the same stable instruction and program
point handles.

The aggregate target `compile` entry points report `TargetCompileEvent`
boundaries around allocation, frame planning, and emission. The allocation
completion event carries `AllocationStatistics`, including edge-transfer
classification, while keeping timing and reporting policy embedding-owned.

The public checkpoints are:

1. selected Target VCode SSA;
2. Target VCode plus Allocation;
3. Target VCode, Allocation, and FrameLayout;
4. verified unlinked code object.

Every checkpoint returns a structured error for malformed input.

## Embedding environment fields

Semantic MachV keeps embedding context access explicit as
`EnvironmentField(field, stability)`. `Stable` means the embedding guarantees
the field value is unchanged for one function invocation; `Mutable` does not
grant that reuse permission. MilkIR owns semantic reuse before lowering;
MachV preserves the remaining occurrences, and targets materialize them without
a second pressure-based reuse policy. Field offsets and runtime layout remain
embedding-provided ABI data.
