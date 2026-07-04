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
  { index, class: Float }
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
pub fn allocatable_regs() -> Array[@machv.PReg] {
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
fn class_for_type(ty : @milkir.Type) -> @machv.RegClass {
  match ty {
    F32 | F64 => Float
    V128 => Vector
    I32 | I64 | Ptr | Ref => Int
  }
}

///|
fn reg_for_value(value : @milkir.Value) -> @machv.Reg {
  Virtual({ id: value.id, class: class_for_type(value.ty) })
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
fn opcode_name(opcode : @milkir.Opcode) -> String {
  match opcode {
    Iadd => "aarch64.iadd"
    Isub => "aarch64.isub"
    Imul => "aarch64.imul"
    IcmpEq => "aarch64.icmp_eq"
    Fadd => "aarch64.fadd"
    Fsub => "aarch64.fsub"
    Fmul => "aarch64.fmul"
    Select => "aarch64.select"
    Load => "aarch64.load"
    Store => "aarch64.store"
    StackAddr(_) => "aarch64.stack_addr"
    Call(symbol) => "aarch64.call:" + symbol.name
    CallIndirect(_) => "aarch64.call_indirect"
    Trap(reason) => "aarch64.trap:" + reason
  }
}

///|
fn lower_inst(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
) -> Unit {
  let lowered = out.new_inst(Target(opcode_name(inst.opcode)))
  add_uses(lowered, inst.args)
  add_defs(lowered, inst.results)
  // TODO(aarch64_target): replace textual target opcodes with selected AArch64
  // machine operations, target constraints, and legalization for non-trivial memory ops.
  block.append(lowered)
}

///|
fn lower_terminator(
  out : @machv.Function,
  block : @machv.Block,
  terminator : @milkir.Terminator,
) -> Unit {
  match terminator {
    Return(values) => {
      let inst = out.new_inst(Return)
      add_uses(inst, values)
      block.append(inst)
    }
    Jump(target, values) => {
      let inst = out.new_inst(Jump(target))
      add_uses(inst, values)
      block.append(inst)
      block.add_successor(target)
    }
    Branch(cond, true_target, true_args, false_target, false_args) => {
      let inst = out.new_inst(Branch(true_target, false_target))
      inst.add_operand(@machv.Operand::use_reg(reg_for_value(cond)))
      add_uses(inst, true_args)
      add_uses(inst, false_args)
      block.append(inst)
      block.add_successor(true_target)
      block.add_successor(false_target)
    }
    TrapExit(reason) => {
      let inst = out.new_inst(Target("aarch64.trap_exit:" + reason))
      block.append(inst)
    }
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
      lower_terminator(out, block, terminator)
    }
  }
  out
}
