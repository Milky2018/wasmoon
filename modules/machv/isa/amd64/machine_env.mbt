///|
/// amd64 machine environment for register allocation (SysV AMD64).
///
/// This provides a Cranelift-style regalloc machine env that matches the
/// register/role assignments in `machv/isa/amd64/roles.mbt`.

///|
fn sysv_callee_saved() -> Array[@abi.PReg] {
  [
    { index: 3, class: Int }, // rbx
    { index: 5, class: Int }, // rbp
    { index: 12, class: Int }, // r12
    { index: 13, class: Int }, // r13
    { index: 14, class: Int }, // r14
    { index: 15, class: Int },
  ] // r15
}

///|
fn allocatable_callee_saved_regs() -> Array[@abi.PReg] {
  let fp_idx = int_reg_index(FP)
  let regs : Array[@abi.PReg] = []
  for r in sysv_callee_saved() {
    // Keep rbp out of the general pool.
    if r.index == fp_idx {
      continue
    }
    regs.push(r)
  }
  regs
}

///|
fn allocatable_scratch_regs() -> Array[@abi.PReg] {
  // SysV caller-saved GPRs excluding rsp/rbp.
  // Order mirrors Cranelift x64 create_reg_env_systemv() preference
  // (rsi,rdi,rax,rcx,rdx,r8,r9,...) as far as our reserved-scratch policy allows.
  // Note: r10/r11 are reserved as scratch via MachineEnvData.scratch_int.
  [
    { index: 6, class: Int }, // rsi
    { index: 7, class: Int }, // rdi
    { index: 0, class: Int }, // rax
    { index: 1, class: Int }, // rcx
    { index: 2, class: Int }, // rdx
    { index: 8, class: Int }, // r8
    { index: 9, class: Int },
  ] // r9
}

///|
fn sysv_arg_fprs() -> Array[@abi.PReg] {
  let regs : Array[@abi.PReg] = []
  for i in 0..<8 {
    regs.push({ index: i, class: Float64 })
  }
  regs
}

///|
fn allocatable_scratch_fprs() -> Array[@abi.PReg] {
  let regs : Array[@abi.PReg] = []
  for i in 0..<16 {
    regs.push({ index: i, class: Float64 })
  }
  regs
}

///|
pub fn build_machine_env(
  _settings : @abi.ABISettings,
  reserved_int_regs : Array[Int],
) -> @spec.MachineEnvData {
  let preferred_int : Array[@abi.PReg] = []
  let nonpreferred_int : Array[@abi.PReg] = []
  let callee_saved_int : Array[@abi.PReg] = []

  // Preferred: caller-saved regs.
  for r in allocatable_scratch_regs() {
    preferred_int.push(r)
  }

  // Nonpreferred: callee-saved regs (excluding pinned/FP).
  for r in allocatable_callee_saved_regs() {
    if reserved_int_regs.contains(r.index) {
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
    // Reserve XMM14/XMM15 as scratch regs for move breaking / lowering temps.
    if r.index < 8 || r.index == 14 || r.index == 15 {
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
    preferred_vector.push({ index: r.index, class: Vector })
  }
  for r in allocatable_scratch_fprs() {
    if r.index < 8 || r.index == 14 || r.index == 15 {
      continue
    }
    preferred_vector.push({ index: r.index, class: Vector })
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
    scratch_int: [int_reg_index(Scratch1), int_reg_index(Scratch2)],
    // Reserve two XMM scratch registers for move breaking / lowering sequences.
    scratch_float: [14, 15],
  }
}
