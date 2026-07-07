///|
pub(all) enum IntRegRole {
  Context
  ContextCache0
  ContextCache1
  ExtraResultsPtr
  Scratch1
  Scratch2
  FP
  LR
  SRet
} derive(Eq, Debug)

///|
pub fn int_reg_index(role : IntRegRole) -> Int {
  match role {
    // TODO(x64_target): separate embedding pinned-register roles from the generic SysV register environment.
    Context => 15
    ContextCache0 => 14
    ContextCache1 => 13
    ExtraResultsPtr => 12
    Scratch1 => 10
    Scratch2 => 11
    FP => 5
    LR => 5
    SRet => 7
  }
}

///|
pub(all) struct TargetSettings {
  enable_pinned_reg : Bool
} derive(Debug)

///|
pub fn TargetSettings::default() -> TargetSettings {
  { enable_pinned_reg: true }
}

///|
pub(all) struct MachineEnvData {
  preferred_int : Array[@machv.PReg]
  nonpreferred_int : Array[@machv.PReg]
  preferred_float : Array[@machv.PReg]
  nonpreferred_float : Array[@machv.PReg]
  preferred_vector : Array[@machv.PReg]
  nonpreferred_vector : Array[@machv.PReg]
  callee_saved_int : Array[@machv.PReg]
  callee_saved_float : Array[@machv.PReg]
  scratch_int : Array[Int]
  scratch_float : Array[Int]
} derive(Debug)

///|
pub fn sysv_callee_saved() -> Array[@machv.PReg] {
  [int_reg(3), int_reg(5), int_reg(12), int_reg(13), int_reg(14), int_reg(15)]
}

///|
pub fn allocatable_callee_saved_regs(
  enable_pinned_reg? : Bool = true,
) -> Array[@machv.PReg] {
  let fp_idx = int_reg_index(FP)
  let context_idx = int_reg_index(Context)
  let regs : Array[@machv.PReg] = []
  for r in sysv_callee_saved() {
    if r.index == fp_idx {
      continue
    }
    if enable_pinned_reg && r.index == context_idx {
      continue
    }
    regs.push(r)
  }
  regs
}

///|
pub fn allocatable_scratch_regs() -> Array[@machv.PReg] {
  [
    int_reg(6),
    int_reg(7),
    int_reg(0),
    int_reg(1),
    int_reg(2),
    int_reg(8),
    int_reg(9),
  ]
}

///|
pub fn sysv_arg_fprs() -> Array[@machv.PReg] {
  let regs : Array[@machv.PReg] = []
  for i in 0..<8 {
    regs.push(float_reg(i))
  }
  regs
}

///|
pub fn allocatable_scratch_fprs() -> Array[@machv.PReg] {
  let regs : Array[@machv.PReg] = []
  for i in 0..<16 {
    regs.push(float_reg(i))
  }
  regs
}

///|
pub fn call_clobbered_gprs() -> Array[@machv.PReg] {
  [
    int_reg(0),
    int_reg(1),
    int_reg(2),
    int_reg(6),
    int_reg(7),
    int_reg(8),
    int_reg(9),
    int_reg(10),
    int_reg(11),
  ]
}

///|
pub fn call_clobbered_fprs() -> Array[@machv.PReg] {
  allocatable_scratch_fprs()
}

///|
pub fn call_clobbered_fprs_same_abi() -> Array[@machv.PReg] {
  call_clobbered_fprs()
}

///|
pub fn build_machine_env(
  settings? : TargetSettings = TargetSettings::default(),
  reserve_context_cache_0? : Bool = false,
  reserve_context_cache_1? : Bool = false,
  reserve_extra_results_ptr? : Bool = false,
) -> MachineEnvData {
  let context_cache_0_idx = int_reg_index(ContextCache0)
  let context_cache_1_idx = int_reg_index(ContextCache1)
  let extra_results_ptr_idx = int_reg_index(ExtraResultsPtr)
  let preferred_int : Array[@machv.PReg] = []
  let nonpreferred_int : Array[@machv.PReg] = []
  let callee_saved_int : Array[@machv.PReg] = []
  for r in allocatable_scratch_regs() {
    preferred_int.push(r)
  }
  for
    r in allocatable_callee_saved_regs(
      enable_pinned_reg=settings.enable_pinned_reg,
    ) {
    if reserve_extra_results_ptr && r.index == extra_results_ptr_idx {
      continue
    }
    if reserve_context_cache_0 && r.index == context_cache_0_idx {
      continue
    }
    if reserve_context_cache_1 && r.index == context_cache_1_idx {
      continue
    }
    nonpreferred_int.push(r)
    callee_saved_int.push(r)
  }

  let preferred_float : Array[@machv.PReg] = []
  let nonpreferred_float : Array[@machv.PReg] = []
  for r in sysv_arg_fprs() {
    preferred_float.push(r)
  }
  for r in allocatable_scratch_fprs() {
    if r.index < 8 || r.index == 14 || r.index == 15 {
      continue
    }
    preferred_float.push(r)
  }
  let callee_saved_float : Array[@machv.PReg] = []

  let preferred_vector : Array[@machv.PReg] = []
  let nonpreferred_vector : Array[@machv.PReg] = []
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
    scratch_int: [int_reg_index(Scratch1), int_reg_index(Scratch2)],
    scratch_float: [14, 15],
  }
}
