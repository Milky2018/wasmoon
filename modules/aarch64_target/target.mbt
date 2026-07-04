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
    CallPtr(_, _) => "aarch64.call_ptr"
    Trap(reason) => "aarch64.trap:" + reason
    Custom(name) => "aarch64.custom:" + name
    Iconst(_) => "aarch64.iconst"
    Fconst(_) => "aarch64.fconst"
    Umulh => "aarch64.umulh"
    Smulh => "aarch64.smulh"
    Sdiv => "aarch64.sdiv"
    Udiv => "aarch64.udiv"
    Srem => "aarch64.srem"
    Urem => "aarch64.urem"
    Band => "aarch64.band"
    Bor => "aarch64.bor"
    Bxor => "aarch64.bxor"
    Bnot => "aarch64.bnot"
    Ishl => "aarch64.ishl"
    Sshr => "aarch64.sshr"
    Ushr => "aarch64.ushr"
    Rotl => "aarch64.rotl"
    Rotr => "aarch64.rotr"
    Clz => "aarch64.clz"
    Ctz => "aarch64.ctz"
    Popcnt => "aarch64.popcnt"
    Icmp(_) => "aarch64.icmp"
    Fdiv => "aarch64.fdiv"
    Fmin => "aarch64.fmin"
    Fmax => "aarch64.fmax"
    Fcmp(_) => "aarch64.fcmp"
    Fneg => "aarch64.fneg"
    Fabs => "aarch64.fabs"
    Fsqrt => "aarch64.fsqrt"
    Fceil => "aarch64.fceil"
    Ffloor => "aarch64.ffloor"
    Ftrunc => "aarch64.ftrunc"
    Fnearest => "aarch64.fnearest"
    Ireduce => "aarch64.ireduce"
    Sextend => "aarch64.sextend"
    Uextend => "aarch64.uextend"
    Fpromote => "aarch64.fpromote"
    Fdemote => "aarch64.fdemote"
    FcvtToSint => "aarch64.fcvt_to_sint"
    FcvtToUint => "aarch64.fcvt_to_uint"
    FcvtToSintSat => "aarch64.fcvt_to_sint_sat"
    FcvtToUintSat => "aarch64.fcvt_to_uint_sat"
    SintToFcvt => "aarch64.sint_to_fcvt"
    UintToFcvt => "aarch64.uint_to_fcvt"
    Bitcast => "aarch64.bitcast"
    Sextend8 => "aarch64.sextend8"
    Sextend16 => "aarch64.sextend16"
    Sextend32 => "aarch64.sextend32"
    Copy => "aarch64.copy"
    LoadPtr(_) => "aarch64.load_ptr"
    StorePtr(_) => "aarch64.store_ptr"
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
    Brz(cond, true_target, false_target)
    | Brnz(cond, true_target, false_target) => {
      let inst = out.new_inst(Branch(true_target, false_target))
      inst.add_operand(@machv.Operand::use_reg(reg_for_value(cond)))
      block.append(inst)
      block.add_successor(true_target)
      block.add_successor(false_target)
    }
    BrTable(index, targets, default_target) => {
      let inst = out.new_inst(Target("aarch64.br_table"))
      inst.add_operand(@machv.Operand::use_reg(reg_for_value(index)))
      block.append(inst)
      for target in targets {
        block.add_successor(target)
      }
      block.add_successor(default_target)
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
