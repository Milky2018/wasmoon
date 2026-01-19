# Cranelift-faithful AppleAarch64 ABI refactor (checklist)

Goal: refactor wasmoon’s JIT ABI to be totally faithful to Cranelift’s AArch64 ABI implementation (AppleAarch64), including the `enable_pinned_reg()` feature flag semantics.

Reference sources (authoritative):
- `/Users/zhengyu/documents/projects/wasmtime/wasmtime/cranelift/codegen/src/isa/aarch64/abi.rs`
- `/Users/zhengyu/documents/projects/wasmtime/wasmtime/cranelift/codegen/src/machinst/abi.rs`

## Phase 0: Ground rules
- [ ] Do not change semantics without a matching Cranelift behavior.
- [ ] When unsure, copy Cranelift’s logic (translated to MoonBit) rather than inventing.
- [ ] Keep `moon test` green at each commit.

## Phase 1: Introduce Cranelift-like settings surface
- [ ] Add a JIT/Codegen settings struct mirroring Cranelift flags.
- [ ] Implement `enable_pinned_reg()` flag (default TBD; keep behavior identical when enabled).
- [ ] Ensure settings reach: regalloc machine env, prologue/epilogue emission, call lowering.

## Phase 2: MachineEnv + regalloc parity
- [ ] Create a MachineEnv representation equivalent to Cranelift’s (allocatable regs, preferred/nonpreferred sets).
- [ ] Make pinned register conditional: when enabled, reserve vmctx pinned reg like Cranelift.
- [ ] Ensure scratch/temp register policy matches Cranelift (e.g. retval temp reg selection).
- [ ] Align call clobber sets to Cranelift’s `get_regs_clobbered_by_call()`.

## Phase 3: VMContext as a special param (Cranelift-style)
- [ ] Replace wasmoon “callee_vmctx + caller_vmctx” ABI with a Cranelift-style `VMContext` special param.
- [ ] Update IR/lowering conventions for params.
- [ ] Update trampolines and any runtime glue that assumes 2 vmctx pointers.
- [ ] Update docs: `docs/jit-abi.md` to reflect Cranelift-faithful ABI.

## Phase 4: Call lowering/emission parity
- [ ] Remove hard-coded assumptions about call target register (no “always x17”).
- [ ] Make indirect calls (`CallPtr`, tail calls) match Cranelift lowering/emission conventions.
- [ ] Ensure temporary regs used by emission do not conflict with call target values.

## Phase 5: Frame layout + prologue/epilogue parity (AppleAarch64)
- [ ] Translate Cranelift’s `compute_frame_layout()` rules.
- [ ] Ensure correct stack alignment rules for AppleAarch64.
- [ ] Ensure saved/restore sets match Cranelift’s `is_reg_saved_in_prologue()` logic.
- [ ] Ensure unwind / stack switching glue remains correct.

## Phase 6: Validation
- [ ] Run `moon test`.
- [ ] Run representative JIT-heavy tests (`testsuite/regalloc_stress_test.mbt`, exceptions, wasi).
- [ ] Run `./wasmoon explore examples/benchmark.wat --stage mc` and sanity-check call sequences.

## Phase 7: Cleanup
- [ ] Remove/replace any legacy “Wasm v3 ABI” comments/assumptions.
- [ ] Ensure all ABI constants and docs match the new Cranelift-faithful scheme.
