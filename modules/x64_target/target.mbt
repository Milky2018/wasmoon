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
pub fn allocatable_regs() -> Array[@machv.PReg] {
  [
    int_reg(0),
    int_reg(1),
    int_reg(2),
    int_reg(3),
    int_reg(6),
    int_reg(7),
    int_reg(8),
    int_reg(9),
  ]
}

///|
fn class_for_type(ty : @milkir.Type) -> @machv.RegClass {
  match ty {
    F32 => Float32
    F64 => Float64
    V128 => Vector
    I32 | I64 | Ptr | Ref => Int
  }
}

///|
fn reg_for_value(value : @milkir.Value) -> @machv.Reg {
  Virtual({ id: value.id, class: class_for_type(value.ty) })
}

///|
fn regs_for_values(values : Array[@milkir.Value]) -> Array[@machv.Reg] {
  values.map(reg_for_value)
}

///|
fn add_uses(inst : @machv.Instruction, values : Array[@milkir.Value]) -> Unit {
  for value in values {
    inst.add_operand(@machv.Operand::use_reg(reg_for_value(value)))
  }
}

///|
fn add_defs(inst : @machv.Instruction, values : Array[@milkir.Value]) -> Unit {
  for value in values {
    inst.add_operand(@machv.Operand::def(reg_for_value(value)))
  }
}

///|
fn intcc_to_machv(cc : @milkir.IntCC) -> @machv.Cond {
  match cc {
    Eq => Eq
    Ne => Ne
    Slt => Lt
    Sle => Le
    Sgt => Gt
    Sge => Ge
    Ult => Ult
    Ule => Ule
    Ugt => Ugt
    Uge => Uge
  }
}

///|
fn floatcc_to_machv(cc : @milkir.FloatCC) -> @machv.Cond {
  match cc {
    Eq => Eq
    Ne => Ne
    Lt => Lt
    Le => Le
    Gt => Gt
    Ge => Ge
  }
}

///|
fn opcode_for(opcode : @milkir.Opcode) -> @machv.Opcode {
  match opcode {
    Iadd => IntAdd
    Isub => IntSub
    Imul => IntMul
    IcmpEq => IntCmp(Eq)
    Icmp(cc) => IntCmp(intcc_to_machv(cc))
    Fadd => FloatAdd
    Fsub => FloatSub
    Fmul => FloatMul
    Umulh => IntMulHigh(false)
    Smulh => IntMulHigh(true)
    Sdiv => IntDiv(true)
    Udiv => IntDiv(false)
    Srem => IntRem(true)
    Urem => IntRem(false)
    Band => IntAnd
    Bor => IntOr
    Bxor => IntXor
    Bnot => IntNot
    Ishl => IntShl
    Sshr => IntShr(true)
    Ushr => IntShr(false)
    Rotl => IntRotl
    Rotr => IntRotr
    Clz => IntClz
    Ctz => IntCtz
    Popcnt => IntPopcnt
    Fdiv => FloatDiv
    Fmin => FloatMin
    Fmax => FloatMax
    Fcmp(cc) => FloatCmp(floatcc_to_machv(cc))
    Fneg => FloatNeg
    Fabs => FloatAbs
    Fsqrt => FloatSqrt
    Fceil => FloatCeil
    Ffloor => FloatFloor
    Ftrunc => FloatTrunc
    Fnearest => FloatNearest
    Ireduce => Ireduce
    Sextend => Sextend
    Uextend => Uextend
    Fpromote => Fpromote
    Fdemote => Fdemote
    FcvtToSint => FcvtToSint
    FcvtToUint => FcvtToUint
    FcvtToSintSat => FcvtToSintSat
    FcvtToUintSat => FcvtToUintSat
    SintToFcvt => SintToFcvt
    UintToFcvt => UintToFcvt
    Bitcast => Bitcast
    Sextend8 => Sextend8
    Sextend16 => Sextend16
    Sextend32 => Sextend32
    Select => Select
    Copy => Move
    Load => LoadMemory
    Store => StoreMemory
    LoadPtr(_) => LoadPtr
    StorePtr(_) => StorePtr
    StackAddr(slot) => StackAddr(slot.id)
    Iconst(value) => IntConst(value)
    Fconst(value) => FloatConst(value)
    Call(symbol) => Call(symbol.name)
    CallIndirect(_) => CallIndirect
    CallPtr(params, results) => CallPtr(params, results)
    Trap(reason) => Trap(reason)
    Custom(name) => Custom(name)
  }
}

///|
fn lower_inst(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
) -> Unit {
  let lowered = out.new_inst(opcode_for(inst.opcode))
  add_uses(lowered, inst.args)
  add_defs(lowered, inst.results)
  // TODO(x64_target): replace textual target opcodes with selected x64 machine
  // operations, target constraints, and legalization for non-trivial memory ops.
  block.append(lowered)
}

///|
fn lower_terminator(
  block : @machv.Block,
  terminator : @milkir.Terminator,
) -> Unit {
  match terminator {
    Return(values) => block.set_terminator(TermReturn(regs_for_values(values)))
    Jump(target, values) =>
      block.set_terminator(TermJump(target, regs_for_values(values)))
    Branch(cond, true_target, true_args, false_target, false_args) =>
      block.set_terminator(
        TermBranch(
          reg_for_value(cond),
          true_target,
          regs_for_values(true_args),
          false_target,
          regs_for_values(false_args),
        ),
      )
    TrapExit(reason) => block.set_terminator(TermTrap(reason))
    Brz(cond, true_target, false_target) =>
      block.set_terminator(
        TermBranchZero(
          reg_for_value(cond),
          false,
          true,
          true_target,
          [],
          false_target,
          [],
        ),
      )
    Brnz(cond, true_target, false_target) =>
      block.set_terminator(
        TermBranchZero(
          reg_for_value(cond),
          true,
          true,
          true_target,
          [],
          false_target,
          [],
        ),
      )
    BrTable(index, targets, default_target) =>
      block.set_terminator(
        TermBrTable(reg_for_value(index), targets, default_target),
      )
  }
}

///|
pub fn lower_function(func : @milkir.Function) -> @machv.Function {
  let out = @machv.Function::new(func.name)
  for milk_block in func.blocks {
    let block = out.new_block()
    for inst in milk_block.instructions {
      lower_inst(out, block, inst)
    }
    if milk_block.terminator is Some(terminator) {
      lower_terminator(block, terminator)
    }
  }
  out
}
