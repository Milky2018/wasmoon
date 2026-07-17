///|
pub(all) enum CallingConvention {
  Aapcs64
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
      int_reg(0),
      int_reg(1),
      int_reg(2),
      int_reg(3),
      int_reg(4),
      int_reg(5),
      int_reg(6),
      int_reg(7),
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
    int_return_regs: [int_reg(0), int_reg(1)],
    float_return_regs: [float_reg(0), float_reg(1)],
    caller_saved_regs: [
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
      int_reg(16),
      int_reg(17),
      float_reg(0),
      float_reg(1),
      float_reg(2),
      float_reg(3),
      float_reg(4),
      float_reg(5),
      float_reg(6),
      float_reg(7),
    ],
    callee_saved_regs: [
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
      float_reg(8),
      float_reg(9),
      float_reg(10),
      float_reg(11),
      float_reg(12),
      float_reg(13),
      float_reg(14),
      float_reg(15),
    ],
  }
}

///|
pub fn target() -> Target {
  {
    triple: "aarch64-unknown-aapcs64",
    calling_convention: Aapcs64,
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
  regs.push(int_reg(int_reg_index(Scratch1)))
  regs.push(int_reg(int_reg_index(Scratch2)))
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
