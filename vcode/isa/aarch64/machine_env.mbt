///|
/// AArch64 machine environment for register allocation (Cranelift-inspired).
///
/// Returns a shared `@spec.MachineEnvData` so the `vcode/isa` facade can convert
/// it into its public `MachineEnv` type without introducing package cycles.

///|
pub fn build_machine_env(
  settings : @abi.ABISettings,
  reserve_mem0_desc : Bool,
  reserve_func_table : Bool,
  reserve_extra_results_ptr : Bool,
) -> @spec.MachineEnvData {
  let preferred_int : Array[@abi.PReg] = []
  let nonpreferred_int : Array[@abi.PReg] = []
  let callee_saved_int : Array[@abi.PReg] = []

  // Preferred GPRs for allocation:
  // Prefer scratch/caller-saved (x0-x15).
  //
  // Note: Wasmoon currently relies on keeping x0-x7 out of the general pool in
  // some places due to call arg constraints; this is enforced elsewhere via
  // fixed-reg constraints. We keep the historical preference ordering here.
  for r in allocatable_scratch_regs() {
    preferred_int.push(r)
  }

  // Nonpreferred callee-saved GPRs: x19-x28, excluding pinned reg when enabled.
  for
    r in allocatable_callee_saved_regs(
      enable_pinned_reg=settings.enable_pinned_reg,
    ) {
    if reserve_extra_results_ptr && r.index == 23 {
      continue
    }
    if reserve_mem0_desc && r.index == @abi.REG_MEM0_DESC {
      continue
    }
    if reserve_func_table && r.index == @abi.REG_FUNC_TABLE {
      continue
    }
    nonpreferred_int.push(r)
    callee_saved_int.push(r)
  }

  // Float regs:
  // Prefer argument regs V0-V7, then caller-saved V18-V31.
  // Callee-saved V8-V15 are non-preferred.
  // V16/V17 are reserved scratch.
  let preferred_float : Array[@abi.PReg] = []
  let nonpreferred_float : Array[@abi.PReg] = []
  for r in aapcs64_arg_fprs() {
    preferred_float.push(r)
  }
  for r in allocatable_scratch_fprs() {
    // Keep V16/V17 non-allocatable as scratch.
    if r.index == 16 || r.index == 17 {
      continue
    }
    preferred_float.push(r)
  }
  let callee_saved_float = callee_saved_fprs()
  for r in callee_saved_float {
    nonpreferred_float.push(r)
  }

  // Vector regs share the same Vn bank as floats.
  // For now, we only use caller-saved regs to keep ABI semantics correct for
  // host calls (AAPCS64 only guarantees low 64-bit preservation of V8-V15).
  let preferred_vector : Array[@abi.PReg] = []
  let nonpreferred_vector : Array[@abi.PReg] = []
  for r in aapcs64_arg_fprs() {
    preferred_vector.push({ index: r.index, class: @abi.Vector })
  }
  for r in allocatable_scratch_fprs() {
    if r.index == 16 || r.index == 17 {
      continue
    }
    preferred_vector.push({ index: r.index, class: @abi.Vector })
  }
  {
    preferred_int,
    nonpreferred_int,
    preferred_float,
    nonpreferred_float,
    preferred_vector,
    nonpreferred_vector,
    callee_saved_int,
    callee_saved_float,
    scratch_int: [@abi.SCRATCH_REG_1, @abi.SCRATCH_REG_2],
    scratch_float: [16, 17],
  }
}
