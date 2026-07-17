# machv

MachV provides the target-neutral semantic machine IR and the shared storage
contracts used after target instruction selection.

## Packages

- `Milky2018/machv`: typed target-neutral SSA, builders, cleanup, printing, and
  verification.
- `Milky2018/machv/vcode`: generic dense Target VCode storage parameterized by
  a target-owned instruction type, plus allocation, frame, and final-emission
  input contracts.

The VCode package does not define a union of AArch64 and x64 instructions.
Each target supplies its own closed instruction type, while the shared package
stores CFG edges, SSA values, stable instruction handles, operand constraints,
clobbers, safepoints, and allocation edits.

## Pipeline boundary

Target lowering consumes verified semantic MachV and produces a complete
`Function[TargetInst]`. Register allocation reads the compact operand side
tables and returns a separate `Allocation`; it does not rewrite Target VCode.
Frame planning and emission consume the same stable instruction and program
point handles.

The public checkpoints are:

1. selected Target VCode SSA;
2. Target VCode plus Allocation;
3. Target VCode, Allocation, and FrameLayout;
4. final emission input.

Every checkpoint returns a structured error for malformed input.
