///|
pub(all) enum CallingConvention {
  SystemV
} derive(Eq, Debug)

///|
pub(all) struct AbiPolicy {
  pointer_size : Int
  stack_alignment : Int
  int_argument_regs : Array[@machv.PReg]
  float_argument_regs : Array[@machv.PReg]
  int_return_regs : Array[@machv.PReg]
  float_return_regs : Array[@machv.PReg]
  caller_saved_regs : Array[@machv.PReg]
  callee_saved_regs : Array[@machv.PReg]
} derive(Debug)

///|
pub(all) struct Target {
  triple : String
  calling_convention : CallingConvention
  abi : AbiPolicy
} derive(Debug)

///|
fn int_reg(index : Int) -> @machv.PReg {
  { index, class: Int }
}

///|
fn float_reg(index : Int) -> @machv.PReg {
  { index, class: Float64 }
}

///|
fn float32_reg(index : Int) -> @machv.PReg {
  { index, class: Float32 }
}

///|
pub fn abi_policy() -> AbiPolicy {
  {
    pointer_size: 8,
    stack_alignment: 16,
    int_argument_regs: [
      int_reg(7),
      int_reg(6),
      int_reg(2),
      int_reg(1),
      int_reg(8),
      int_reg(9),
    ],
    float_argument_regs: [
      float_reg(0),
      float_reg(1),
      float_reg(2),
      float_reg(3),
      float_reg(4),
      float_reg(5),
      float_reg(6),
      float_reg(7),
    ],
    int_return_regs: [int_reg(0), int_reg(3)],
    float_return_regs: [float_reg(0), float_reg(1)],
    caller_saved_regs: [
      int_reg(0),
      int_reg(1),
      int_reg(2),
      int_reg(6),
      int_reg(7),
      int_reg(8),
      int_reg(9),
      int_reg(10),
      int_reg(11),
      float_reg(0),
      float_reg(1),
      float_reg(2),
      float_reg(3),
      float_reg(4),
      float_reg(5),
      float_reg(6),
      float_reg(7),
      float_reg(8),
      float_reg(9),
      float_reg(10),
      float_reg(11),
      float_reg(12),
      float_reg(13),
      float_reg(14),
      float_reg(15),
    ],
    callee_saved_regs: [
      int_reg(3),
      int_reg(5),
      int_reg(12),
      int_reg(13),
      int_reg(14),
      int_reg(15),
    ],
  }
}

///|
pub fn target() -> Target {
  {
    triple: "x86_64-unknown-systemv",
    calling_convention: SystemV,
    abi: abi_policy(),
  }
}

///|
pub fn allocatable_regs(
  reserved_int_regs? : Array[Int] = [],
) -> Array[@machv.PReg] {
  let env = build_machine_env(reserved_int_regs~)
  let regs : Array[@machv.PReg] = []
  for r in env.preferred_int {
    regs.push(r)
  }
  for r in env.nonpreferred_int {
    regs.push(r)
  }
  for r in env.preferred_float {
    regs.push(float32_reg(r.index))
    regs.push(r)
  }
  for r in env.nonpreferred_float {
    regs.push(float32_reg(r.index))
    regs.push(r)
  }
  for r in env.preferred_vector {
    regs.push(r)
  }
  for r in env.nonpreferred_vector {
    regs.push(r)
  }
  regs
}

///|
fn default_call_conv() -> @abi.CallConventionLayout {
  {
    context_arg: { index: 7, class: Int },
    user_arg_gprs: [
      { index: 6, class: Int },
      { index: 2, class: Int },
      { index: 1, class: Int },
      { index: 8, class: Int },
      { index: 9, class: Int },
    ],
    arg_fprs: [
      float_reg(0),
      float_reg(1),
      float_reg(2),
      float_reg(3),
      float_reg(4),
      float_reg(5),
      float_reg(6),
      float_reg(7),
    ],
    ret_gprs: [
      int_reg(0),
      int_reg(3),
      int_reg(2),
      int_reg(1),
      int_reg(8),
      int_reg(9),
      int_reg(6),
      int_reg(7),
    ],
    ret_fprs: [
      float_reg(0),
      float_reg(1),
      float_reg(2),
      float_reg(3),
      float_reg(4),
      float_reg(5),
      float_reg(6),
      float_reg(7),
    ],
  }
}

///|
pub fn lower_function(
  func : @milkir.Function,
  return_area_base_reg? : @machv.PReg? = None,
) -> @machv.Function raise @milkir.VerifyError {
  ignore(return_area_base_reg)
  lower_function_with_call_conv(func, default_call_conv())
}

///|
pub fn lower_function_with_call_conv(
  func : @milkir.Function,
  call_conv_layout : @abi.CallConventionLayout,
  return_area_base_reg? : @machv.PReg? = None,
) -> @machv.Function raise @milkir.VerifyError {
  ignore(return_area_base_reg)
  @lower.lower_function(
    func,
    isa=AMD64,
    embedding_abi=Some(EmbeddingABI(call_conv_layout)),
  )
}
