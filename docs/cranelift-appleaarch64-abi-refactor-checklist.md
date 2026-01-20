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
- [x] Add a JIT/Codegen settings struct mirroring Cranelift flags.
- [x] Implement `enable_pinned_reg()` flag (default pinned on for now).
- [x] Ensure settings reach: regalloc machine env, prologue emission, call lowering.

## Phase 2: MachineEnv + regalloc parity
- [x] Translate Cranelift `create_reg_env()` into wasmoon’s `AArch64MachineEnv` (preferred/nonpreferred by class).
- [x] Make pinned register conditional exactly like Cranelift (pinned reg is X21).
- [x] Stop treating X19 as a permanently-reserved vmctx register.
- [ ] Align call clobber sets to Cranelift `default_aapcs_clobbers()` (clobber v0-v31).
- [ ] Note/resolve remaining deviations (e.g. reserved V16/V17 scratch and not-yet-regalloc2-equivalent modeling).

## Phase 3: VMContext as a special param (Cranelift-style)
- [x] Replace wasmoon “callee_vmctx + caller_vmctx” ABI with a Cranelift-style `VMContext` special param.
- [x] Update IR/lowering conventions for params.
- [x] Update trampolines and any runtime glue that assumes 2 vmctx pointers.
- [x] Update docs: `docs/jit-abi.md` to reflect Cranelift-faithful ABI.

## Phase 4: Call lowering/emission parity
- [x] Remove hard-coded assumptions about call target register (no “always x17”).
- [x] Make indirect calls (`CallPtr`, tail calls) match Cranelift lowering/emission conventions.
- [x] Ensure temporary regs used by emission do not conflict with call target values.

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
