///|
/// x86_64 machine environment for register allocation (SysV AMD64).
///
/// This provides a Cranelift-style regalloc machine env that matches the
/// register/role assignments in `vcode/isa/x86_64/roles.mbt`.

///|
fn sysv_callee_saved() -> Array[@abi.PReg] {
  [
    { index: 3, class: @abi.Int }, // rbx
    { index: 5, class: @abi.Int }, // rbp
    { index: 12, class: @abi.Int }, // r12
    { index: 13, class: @abi.Int }, // r13
    { index: 14, class: @abi.Int }, // r14
    { index: 15, class: @abi.Int },
  ] // r15
}

///|
fn allocatable_callee_saved_regs(enable_pinned_reg : Bool) -> Array[@abi.PReg] {
  let fp_idx = int_reg_index(@spec.IntRegRole::FP)
  let vmctx_idx = int_reg_index(@spec.IntRegRole::Vmctx)
  let regs : Array[@abi.PReg] = []
  for r in sysv_callee_saved() {
    // Keep rbp out of the general pool.
    if r.index == fp_idx {
      continue
    }
    if enable_pinned_reg && r.index == vmctx_idx {
      continue
    }
    regs.push(r)
  }
  regs
}

///|
fn allocatable_scratch_regs() -> Array[@abi.PReg] {
  // SysV caller-saved GPRs excluding rsp/rbp.
  // Note: r10/r11 are reserved as scratch via MachineEnvData.scratch_int.
  [
    { index: 0, class: @abi.Int }, // rax
    { index: 1, class: @abi.Int }, // rcx
    { index: 2, class: @abi.Int }, // rdx
    { index: 6, class: @abi.Int }, // rsi
    { index: 7, class: @abi.Int }, // rdi
    { index: 8, class: @abi.Int }, // r8
    { index: 9, class: @abi.Int },
  ] // r9
}

///|
fn sysv_arg_fprs() -> Array[@abi.PReg] {
  let regs : Array[@abi.PReg] = []
  for i in 0..<8 {
    regs.push({ index: i, class: @abi.Float64 })
  }
  regs
}

///|
fn allocatable_scratch_fprs() -> Array[@abi.PReg] {
  let regs : Array[@abi.PReg] = []
  for i in 0..<16 {
    regs.push({ index: i, class: @abi.Float64 })
  }
  regs
}

///|
pub fn build_machine_env(
  settings : @abi.ABISettings,
  reserve_mem0_desc : Bool,
  reserve_func_table : Bool,
  reserve_extra_results_ptr : Bool,
) -> @spec.MachineEnvData {
  let mem0_desc_idx = int_reg_index(@spec.IntRegRole::Mem0Desc)
  let func_table_idx = int_reg_index(@spec.IntRegRole::FuncTable)
  let extra_results_ptr_idx = int_reg_index(@spec.IntRegRole::ExtraResultsPtr)
  let preferred_int : Array[@abi.PReg] = []
  let nonpreferred_int : Array[@abi.PReg] = []
  let callee_saved_int : Array[@abi.PReg] = []

  // Preferred: caller-saved regs.
  for r in allocatable_scratch_regs() {
    preferred_int.push(r)
  }

  // Nonpreferred: callee-saved regs (excluding pinned/FP).
  for r in allocatable_callee_saved_regs(settings.enable_pinned_reg) {
    if reserve_extra_results_ptr && r.index == extra_results_ptr_idx {
      continue
    }
    if reserve_mem0_desc && r.index == mem0_desc_idx {
      continue
    }
    if reserve_func_table && r.index == func_table_idx {
      continue
    }
    nonpreferred_int.push(r)
    callee_saved_int.push(r)
  }

  // Float regs (XMM): all caller-saved on SysV.
  let preferred_float : Array[@abi.PReg] = []
  let nonpreferred_float : Array[@abi.PReg] = []
  for r in sysv_arg_fprs() {
    preferred_float.push(r)
  }
  for r in allocatable_scratch_fprs() {
    // Avoid duplicating XMM0-7 already in preferred list.
    if r.index < 8 {
      continue
    }
    preferred_float.push(r)
  }

  // No callee-saved floating-point regs on SysV.
  let callee_saved_float : Array[@abi.PReg] = []

  // Vector regs share the same XMM bank.
  let preferred_vector : Array[@abi.PReg] = []
  let nonpreferred_vector : Array[@abi.PReg] = []
  for r in sysv_arg_fprs() {
    preferred_vector.push({ index: r.index, class: @abi.Vector })
  }
  for r in allocatable_scratch_fprs() {
    if r.index < 8 {
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
    // Reserve scratch regs for lowering/emission.
    scratch_int: [
      int_reg_index(@spec.IntRegRole::Scratch1),
      int_reg_index(@spec.IntRegRole::Scratch2),
    ],
    scratch_float: [],
  }
}
