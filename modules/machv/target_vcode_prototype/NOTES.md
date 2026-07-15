# Prototype Verdict

Question: does a generic MoonBit VCode shell plus a small static `AllocatableInst` projection keep AArch64 and AMD64 instruction types separate while sharing CFG and regalloc traversal?

Human verdict: accepted. Keep the generic shared shell, statically typed AArch64/AMD64 pipelines, and operand-only allocation projection. The architecture may add one later RISC-V instruction adapter, but does not need an open-ended runtime target plugin system.

Observed constraints:

- `VCodeFunction[Inst]`, `VCodeBlock[Inst]`, and `Terminator[Inst]` compile without placing a trait bound on the shared storage types; only operations that inspect instructions need a bound.
- `VCodeFunction[AArch64Inst]` rejects an `AMD64Inst` constructor at compile time. A temporary negative probe produced `has type: AMD64Inst, wanted: AArch64Inst` and was then deleted.
- A one-method static `AllocatableInst` trait is sufficient for the prototype's shared traversal. It exposes only operands; the shell itself derives body/terminator position. The resulting `RegallocView` contains stable block/instruction handles, roles, operands, and constraints, but no target opcode, target name, or mnemonic.
- Printing needs a separate `RenderInst` interface. Keeping it separate prevents regalloc from learning display or target-selection details.
- MoonBit does not provide an implicit existential `VCodeFunction[Inst]` that can hold either target at runtime. Target selection must branch into statically typed AArch64 and AMD64 pipelines, or a later design must introduce an explicit orchestration adapter. It does not require a shared opcode union.
- The prototype uses one target instruction type for body and terminator nodes, with successor edges stored by the shared shell. A production verifier must reject body-only instructions in terminator position and terminators in body position.
- Owner tokens, complete CFG verification, allocation results, move/spill insertion, target lowering, and emission remain deliberately omitted.

Deletion condition: remove this prototype package after [Define the MachV target-lowering interface](../../../issues/ISS-186.md) absorbs the accepted type relationships into its durable decision.
