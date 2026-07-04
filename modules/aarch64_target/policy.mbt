///|
pub(all) enum IntRegRole {
  Vmctx
  Mem0Desc
  FuncTable
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
    Vmctx => 21
    Mem0Desc => 20
    FuncTable => 19
    ExtraResultsPtr => 23
    Scratch1 => 16
    Scratch2 => 17
    FP => 29
    LR => 30
    SRet => 8
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
pub fn aapcs64_arg_gprs() -> Array[@machv.PReg] {
  [
    int_reg(0),
    int_reg(1),
    int_reg(2),
    int_reg(3),
    int_reg(4),
    int_reg(5),
    int_reg(6),
    int_reg(7),
  ]
}

///|
pub fn aapcs64_ret_gprs() -> Array[@machv.PReg] {
  aapcs64_arg_gprs()
}

///|
pub fn aapcs64_callee_saved() -> Array[@machv.PReg] {
  [
    int_reg(19),
    int_reg(20),
    int_reg(21),
    int_reg(22),
    int_reg(23),
    int_reg(24),
    int_reg(25),
    int_reg(26),
    int_reg(27),
    int_reg(28),
    int_reg(29),
    int_reg(30),
  ]
}

///|
pub fn allocatable_scratch_regs() -> Array[@machv.PReg] {
  [
    int_reg(0),
    int_reg(1),
    int_reg(2),
    int_reg(3),
    int_reg(4),
    int_reg(5),
    int_reg(6),
    int_reg(7),
    int_reg(8),
    int_reg(9),
    int_reg(10),
    int_reg(11),
    int_reg(12),
    int_reg(13),
    int_reg(14),
    int_reg(15),
  ]
}

///|
pub fn allocatable_callee_saved_regs(
  enable_pinned_reg? : Bool = true,
) -> Array[@machv.PReg] {
  let regs : Array[@machv.PReg] = []
  let fp_idx = int_reg_index(FP)
  let lr_idx = int_reg_index(LR)
  let vmctx_idx = int_reg_index(Vmctx)
  for r in aapcs64_callee_saved() {
    if r.index == fp_idx || r.index == lr_idx {
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
pub fn aapcs64_arg_fprs() -> Array[@machv.PReg] {
  [
    float_reg(0),
    float_reg(1),
    float_reg(2),
    float_reg(3),
    float_reg(4),
    float_reg(5),
    float_reg(6),
    float_reg(7),
  ]
}

///|
pub fn aapcs64_ret_fprs() -> Array[@machv.PReg] {
  aapcs64_arg_fprs()
}

///|
pub fn wasm_vmctx_arg_preg() -> @machv.PReg {
  int_reg(0)
}

///|
pub fn wasm_user_arg_gprs() -> Array[@machv.PReg] {
  [
    int_reg(1),
    int_reg(2),
    int_reg(3),
    int_reg(4),
    int_reg(5),
    int_reg(6),
    int_reg(7),
  ]
}

///|
pub fn wasm_arg_fprs() -> Array[@machv.PReg] {
  aapcs64_arg_fprs()
}

///|
pub fn wasm_ret_gprs() -> Array[@machv.PReg] {
  aapcs64_ret_gprs()
}

///|
pub fn wasm_ret_fprs() -> Array[@machv.PReg] {
  aapcs64_ret_fprs()
}

///|
pub fn callee_saved_fprs() -> Array[@machv.PReg] {
  [
    float_reg(8),
    float_reg(9),
    float_reg(10),
    float_reg(11),
    float_reg(12),
    float_reg(13),
    float_reg(14),
    float_reg(15),
  ]
}

///|
pub fn allocatable_scratch_fprs() -> Array[@machv.PReg] {
  let regs : Array[@machv.PReg] = []
  for i in 16..<32 {
    regs.push(float_reg(i))
  }
  regs
}

///|
pub fn call_clobbered_gprs() -> Array[@machv.PReg] {
  let regs : Array[@machv.PReg] = []
  for i in 0..<18 {
    regs.push(int_reg(i))
  }
  regs
}

///|
pub fn call_clobbered_fprs() -> Array[@machv.PReg] {
  let regs : Array[@machv.PReg] = []
  for i in 0..<32 {
    regs.push(float_reg(i))
  }
  regs
}

///|
pub fn call_clobbered_fprs_same_abi() -> Array[@machv.PReg] {
  let regs : Array[@machv.PReg] = []
  for i in 0..<32 {
    if i >= 8 && i <= 15 {
      continue
    }
    regs.push(float_reg(i))
  }
  regs
}

///|
pub fn build_machine_env(
  settings? : TargetSettings = TargetSettings::default(),
  reserve_mem0_desc? : Bool = false,
  reserve_func_table? : Bool = false,
  reserve_extra_results_ptr? : Bool = false,
) -> MachineEnvData {
  let mem0_desc_idx = int_reg_index(Mem0Desc)
  let func_table_idx = int_reg_index(FuncTable)
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
    if reserve_mem0_desc && r.index == mem0_desc_idx {
      continue
    }
    if reserve_func_table && r.index == func_table_idx {
      continue
    }
    nonpreferred_int.push(r)
    callee_saved_int.push(r)
  }

  let preferred_float : Array[@machv.PReg] = []
  let nonpreferred_float : Array[@machv.PReg] = []
  for r in aapcs64_arg_fprs() {
    preferred_float.push(r)
  }
  for r in allocatable_scratch_fprs() {
    if r.index == 16 || r.index == 17 {
      continue
    }
    preferred_float.push(r)
  }
  let callee_saved_float = callee_saved_fprs()
  for r in callee_saved_float {
    nonpreferred_float.push(r)
  }

  let preferred_vector : Array[@machv.PReg] = []
  let nonpreferred_vector : Array[@machv.PReg] = []
  for r in aapcs64_arg_fprs() {
    preferred_vector.push({ index: r.index, class: Vector })
  }
  for r in allocatable_scratch_fprs() {
    if r.index == 16 || r.index == 17 {
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
    scratch_float: [16, 17],
  }
}
