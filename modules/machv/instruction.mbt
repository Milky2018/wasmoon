///|
pub(all) enum Opcode {
  Target(String)
  Move
  IntConst(Int64)
  FloatConst(Double)
  IntAdd
  IntSub
  IntMul
  IntMulHigh(Bool)
  IntDiv(Bool)
  IntRem(Bool)
  IntAnd
  IntOr
  IntXor
  IntNot
  IntShl
  IntShr(Bool)
  IntRotl
  IntRotr
  IntClz
  IntCtz
  IntPopcnt
  IntCmp(Cond)
  FloatAdd
  FloatSub
  FloatMul
  FloatDiv
  FloatMin
  FloatMax
  FloatCmp(Cond)
  FloatNeg
  FloatAbs
  FloatSqrt
  FloatCeil
  FloatFloor
  FloatTrunc
  FloatNearest
  Ireduce
  Sextend
  Uextend
  Fpromote
  Fdemote
  FcvtToSint
  FcvtToUint
  FcvtToSintSat
  FcvtToUintSat
  SintToFcvt
  UintToFcvt
  Bitcast
  Sextend8
  Sextend16
  Sextend32
  Select
  LoadMemory(MemType, Int)
  StoreMemory(MemType, Int)
  LoadPtr(MemType, Int)
  LoadPtrNarrow(Int, Bool, Int)
  StorePtr(MemType, Int)
  StorePtrNarrow(Int, Int)
  StackAddr(Int)
  CallIndirect
  CallPtr(Int, Int)
  Custom(String)
  Load(StackSlot)
  Store(StackSlot)
  Call(String)
  Trap(String)
  Jump(Int)
  Branch(Int, Int)
  Return
} derive(Eq, Debug)

///|
pub(all) enum MemType {
  MemI32
  MemI64
  MemF32
  MemF64
  MemV128
  MemPtr
} derive(Eq, Debug)

///|
pub(all) struct Constraint {
  operand_index : Int
  allowed_regs : Array[PReg]
} derive(Eq, Debug)

///|
pub(all) struct Instruction {
  id : Int
  opcode : Opcode
  operands : Array[Operand]
  clobbers : Array[PReg]
  constraints : Array[Constraint]
  abi_arg_locations : Array[AbiValueLocation]
  abi_result_locations : Array[AbiValueLocation]
  mut stack_effect : StackEffect
} derive(Eq, Debug)

///|
pub(all) enum Cond {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  Ult
  Ule
  Ugt
  Uge
  Mi
  Parity
  NotParity
  Custom(String)
} derive(Eq, Debug)

///|
pub(all) enum Terminator {
  TermJump(Int, Array[Reg])
  TermBranch(Reg, Int, Array[Reg], Int, Array[Reg])
  TermBranchCmp(Reg, Reg, Cond, Bool, Int, Array[Reg], Int, Array[Reg])
  TermBranchZero(Reg, Bool, Bool, Int, Array[Reg], Int, Array[Reg])
  TermBranchCmpImm(Reg, Int, Cond, Bool, Int, Array[Reg], Int, Array[Reg])
  TermReturn(Array[Reg])
  TermTrap(String)
  TermBrTable(Reg, Array[Int], Int)
} derive(Eq, Debug)

///|
pub fn Instruction::new(id : Int, opcode : Opcode) -> Instruction {
  {
    id,
    opcode,
    operands: [],
    clobbers: [],
    constraints: [],
    abi_arg_locations: [],
    abi_result_locations: [],
    stack_effect: None,
  }
}

///|
pub fn Instruction::add_operand(self : Instruction, operand : Operand) -> Unit {
  self.operands.push(operand)
}

///|
pub fn Instruction::add_clobber(self : Instruction, preg : PReg) -> Unit {
  self.clobbers.push(preg)
}

///|
pub fn Instruction::add_constraint(
  self : Instruction,
  constraint : Constraint,
) -> Unit {
  self.constraints.push(constraint)
}

///|
pub fn Instruction::add_abi_arg_location(
  self : Instruction,
  location : AbiValueLocation,
) -> Unit {
  self.abi_arg_locations.push(location)
}

///|
pub fn Instruction::add_abi_result_location(
  self : Instruction,
  location : AbiValueLocation,
) -> Unit {
  self.abi_result_locations.push(location)
}

///|
pub fn Instruction::set_stack_effect(
  self : Instruction,
  effect : StackEffect,
) -> Unit {
  self.stack_effect = effect
}
