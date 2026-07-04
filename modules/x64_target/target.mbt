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
  { index, class: Float }
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
    Iadd => "x64.iadd"
    Isub => "x64.isub"
    Imul => "x64.imul"
    IcmpEq => "x64.icmp_eq"
    Fadd => "x64.fadd"
    Fsub => "x64.fsub"
    Fmul => "x64.fmul"
    Select => "x64.select"
    Load => "x64.load"
    Store => "x64.store"
    StackAddr(_) => "x64.stack_addr"
    Call(symbol) => "x64.call:" + symbol.name
    CallIndirect(_) => "x64.call_indirect"
    CallPtr(_, _) => "x64.call_ptr"
    Trap(reason) => "x64.trap:" + reason
    Custom(name) => "x64.custom:" + name
    Iconst(_) => "x64.iconst"
    Fconst(_) => "x64.fconst"
    Umulh => "x64.umulh"
    Smulh => "x64.smulh"
    Sdiv => "x64.sdiv"
    Udiv => "x64.udiv"
    Srem => "x64.srem"
    Urem => "x64.urem"
    Band => "x64.band"
    Bor => "x64.bor"
    Bxor => "x64.bxor"
    Bnot => "x64.bnot"
    Ishl => "x64.ishl"
    Sshr => "x64.sshr"
    Ushr => "x64.ushr"
    Rotl => "x64.rotl"
    Rotr => "x64.rotr"
    Clz => "x64.clz"
    Ctz => "x64.ctz"
    Popcnt => "x64.popcnt"
    Icmp(_) => "x64.icmp"
    Fdiv => "x64.fdiv"
    Fmin => "x64.fmin"
    Fmax => "x64.fmax"
    Fcmp(_) => "x64.fcmp"
    Fneg => "x64.fneg"
    Fabs => "x64.fabs"
    Fsqrt => "x64.fsqrt"
    Fceil => "x64.fceil"
    Ffloor => "x64.ffloor"
    Ftrunc => "x64.ftrunc"
    Fnearest => "x64.fnearest"
    Ireduce => "x64.ireduce"
    Sextend => "x64.sextend"
    Uextend => "x64.uextend"
    Fpromote => "x64.fpromote"
    Fdemote => "x64.fdemote"
    FcvtToSint => "x64.fcvt_to_sint"
    FcvtToUint => "x64.fcvt_to_uint"
    FcvtToSintSat => "x64.fcvt_to_sint_sat"
    FcvtToUintSat => "x64.fcvt_to_uint_sat"
    SintToFcvt => "x64.sint_to_fcvt"
    UintToFcvt => "x64.uint_to_fcvt"
    Bitcast => "x64.bitcast"
    Sextend8 => "x64.sextend8"
    Sextend16 => "x64.sextend16"
    Sextend32 => "x64.sextend32"
    Copy => "x64.copy"
    LoadPtr(_) => "x64.load_ptr"
    StorePtr(_) => "x64.store_ptr"
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
  // TODO(x64_target): replace textual target opcodes with selected x64 machine
  // operations, target constraints, and legalization for non-trivial memory ops.
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
      let inst = out.new_inst(Target("x64.trap_exit:" + reason))
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
      let inst = out.new_inst(Target("x64.br_table"))
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
