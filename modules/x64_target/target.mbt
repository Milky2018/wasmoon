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
pub fn allocatable_regs() -> Array[@machv.PReg] {
  let env = build_machine_env()
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
fn preg_with_class(preg : @machv.PReg, class : @machv.RegClass) -> @machv.PReg {
  { index: preg.index, class }
}

///|
fn add_fixed_constraint(
  inst : @machv.Instruction,
  operand_index : Int,
  preg : @machv.PReg,
) -> Unit {
  inst.add_constraint({ operand_index, allowed_regs: [preg] })
}

///|
fn add_call_abi_constraints(
  inst : @machv.Instruction,
  args : Array[@milkir.Value],
  results : Array[@milkir.Value],
) -> Unit {
  let abi = abi_policy()
  let mut int_arg_idx = 0
  let mut float_arg_idx = 0
  for operand_index, arg in args {
    match class_for_type(arg.ty) {
      Int =>
        if int_arg_idx < abi.int_argument_regs.length() {
          add_fixed_constraint(
            inst,
            operand_index,
            abi.int_argument_regs[int_arg_idx],
          )
          int_arg_idx = int_arg_idx + 1
        }
      Float32 | Float64 | Vector =>
        if float_arg_idx < abi.float_argument_regs.length() {
          let class = class_for_type(arg.ty)
          add_fixed_constraint(
            inst,
            operand_index,
            preg_with_class(abi.float_argument_regs[float_arg_idx], class),
          )
          float_arg_idx = float_arg_idx + 1
        }
    }
  }
  let mut int_result_idx = 0
  let mut float_result_idx = 0
  for result_index, result in results {
    let operand_index = args.length() + result_index
    match class_for_type(result.ty) {
      Int =>
        if int_result_idx < abi.int_return_regs.length() {
          add_fixed_constraint(
            inst,
            operand_index,
            abi.int_return_regs[int_result_idx],
          )
          int_result_idx = int_result_idx + 1
        }
      Float32 | Float64 | Vector =>
        if float_result_idx < abi.float_return_regs.length() {
          let class = class_for_type(result.ty)
          add_fixed_constraint(
            inst,
            operand_index,
            preg_with_class(abi.float_return_regs[float_result_idx], class),
          )
          float_result_idx = float_result_idx + 1
        }
    }
  }
  // TODO(x64_target): materialize overflow stack arguments once MachV carries
  // outgoing stack-argument effects in a target-independent form.
  for preg in abi.caller_saved_regs {
    inst.add_clobber(preg)
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
fn mem_type_for_type(ty : @milkir.Type) -> @machv.MemType {
  match ty {
    I32 => MemI32
    I64 => MemI64
    F32 => MemF32
    F64 => MemF64
    V128 => MemV128
    Ptr | Ref => MemPtr
  }
}

///|
fn find_iconst(func : @milkir.Function, value : @milkir.Value) -> Int64? {
  for block in func.blocks {
    for inst in block.instructions {
      if inst.results.length() == 1 && inst.results[0].id == value.id {
        if inst.opcode is Iconst(offset) {
          return Some(offset)
        }
        return None
      }
    }
  }
  None
}

///|
fn const_offset_arg(
  func : @milkir.Function,
  args : Array[@milkir.Value],
  index : Int,
) -> Int {
  if index < args.length() {
    match find_iconst(func, args[index]) {
      Some(offset) => offset.to_int()
      None => 0
    }
  } else {
    0
  }
}

///|
fn lower_int_div(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
  signed : Bool,
) -> Unit {
  let lhs_tmp = out.new_vreg(Int)
  let rhs_tmp = out.new_vreg(Int)
  let lhs_move = out.new_inst(Move)
  lhs_move.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
  lhs_move.add_operand(@machv.Operand::def(Virtual(lhs_tmp)))
  block.append(lhs_move)
  let rhs_move = out.new_inst(Move)
  rhs_move.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[1])))
  rhs_move.add_operand(@machv.Operand::def(Virtual(rhs_tmp)))
  block.append(rhs_move)

  let div = out.new_inst(IntDiv(signed))
  div.add_operand(@machv.Operand::use_reg(Virtual(lhs_tmp)))
  div.add_operand(@machv.Operand::use_reg(Virtual(rhs_tmp)))
  div.add_operand(@machv.Operand::def(Virtual(lhs_tmp)))
  // TODO(x64_target): make the RDX side effect a first-class tied physical-def
  // operand instead of a fake virtual result.
  let rdx_tmp = out.new_vreg(Int)
  div.add_operand(@machv.Operand::def(Virtual(rdx_tmp)))
  add_fixed_constraint(div, 0, int_reg(0))
  add_fixed_constraint(div, 1, int_reg(8))
  add_fixed_constraint(div, 2, int_reg(0))
  add_fixed_constraint(div, 3, int_reg(3))
  block.append(div)
  let result_move = out.new_inst(Move)
  result_move.add_operand(@machv.Operand::use_reg(Virtual(lhs_tmp)))
  add_defs(result_move, inst.results)
  block.append(result_move)
}

///|
fn lower_int_rem(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
  signed : Bool,
) -> Unit {
  let lhs_tmp = out.new_vreg(Int)
  let rhs_tmp = out.new_vreg(Int)
  let lhs_move = out.new_inst(Move)
  lhs_move.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
  lhs_move.add_operand(@machv.Operand::def(Virtual(lhs_tmp)))
  block.append(lhs_move)
  let rhs_move = out.new_inst(Move)
  rhs_move.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[1])))
  rhs_move.add_operand(@machv.Operand::def(Virtual(rhs_tmp)))
  block.append(rhs_move)

  let rem = out.new_inst(IntRem(signed))
  rem.add_operand(@machv.Operand::use_reg(Virtual(lhs_tmp)))
  rem.add_operand(@machv.Operand::use_reg(Virtual(rhs_tmp)))
  let rdx_tmp = out.new_vreg(Int)
  rem.add_operand(@machv.Operand::def(Virtual(rdx_tmp)))
  // TODO(x64_target): make the RAX quotient side effect a first-class tied
  // physical-def operand instead of a fake virtual result.
  rem.add_operand(@machv.Operand::def(Virtual(lhs_tmp)))
  add_fixed_constraint(rem, 0, int_reg(0))
  add_fixed_constraint(rem, 1, int_reg(8))
  add_fixed_constraint(rem, 2, int_reg(3))
  add_fixed_constraint(rem, 3, int_reg(0))
  block.append(rem)
  let result_move = out.new_inst(Move)
  result_move.add_operand(@machv.Operand::use_reg(Virtual(rdx_tmp)))
  add_defs(result_move, inst.results)
  block.append(result_move)
}

///|
fn append_int_const(
  out : @machv.Function,
  block : @machv.Block,
  value : Int64,
) -> @machv.VReg {
  let dst = out.new_vreg(Int)
  let load = out.new_inst(IntConst(value))
  load.add_operand(@machv.Operand::def(Virtual(dst)))
  block.append(load)
  dst
}

///|
fn append_int_binop(
  out : @machv.Function,
  block : @machv.Block,
  opcode : @machv.Opcode,
  lhs : @machv.Reg,
  rhs : @machv.Reg,
) -> @machv.VReg {
  let dst = out.new_vreg(Int)
  let op = out.new_inst(opcode)
  op.add_operand(@machv.Operand::use_reg(lhs))
  op.add_operand(@machv.Operand::use_reg(rhs))
  op.add_operand(@machv.Operand::def(Virtual(dst)))
  block.append(op)
  dst
}

///|
fn append_int_move_result(
  block : @machv.Block,
  out : @machv.Function,
  src : @machv.Reg,
  results : Array[@milkir.Value],
) -> Unit {
  let move_inst = out.new_inst(Move)
  move_inst.add_operand(@machv.Operand::use_reg(src))
  add_defs(move_inst, results)
  block.append(move_inst)
}

///|
fn append_int_shift(
  out : @machv.Function,
  block : @machv.Block,
  value : @machv.Reg,
  count : @machv.Reg,
) -> @machv.VReg {
  let value_tmp = out.new_vreg(Int)
  let count_tmp = out.new_vreg(Int)
  let value_move = out.new_inst(Move)
  value_move.add_operand(@machv.Operand::use_reg(value))
  value_move.add_operand(@machv.Operand::def(Virtual(value_tmp)))
  block.append(value_move)
  let count_move = out.new_inst(Move)
  count_move.add_operand(@machv.Operand::use_reg(count))
  count_move.add_operand(@machv.Operand::def(Virtual(count_tmp)))
  block.append(count_move)
  let shift = out.new_inst(IntShr(false))
  shift.add_operand(@machv.Operand::use_reg(Virtual(value_tmp)))
  shift.add_operand(@machv.Operand::use_reg(Virtual(count_tmp)))
  shift.add_operand(@machv.Operand::def(Virtual(value_tmp)))
  add_fixed_constraint(shift, 1, int_reg(1))
  block.append(shift)
  value_tmp
}

///|
fn lower_int_popcnt(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
) -> Unit {
  guard inst.args.length() == 1 && inst.results.length() == 1 else { return }
  let input : @machv.Reg = if inst.args[0].ty == I32 {
    let mask32 = append_int_const(out, block, 0xffffffffL)
    let masked = append_int_binop(
      out,
      block,
      IntAnd,
      reg_for_value(inst.args[0]),
      Virtual(mask32),
    )
    Virtual(masked)
  } else {
    reg_for_value(inst.args[0])
  }
  let one = append_int_const(out, block, 1L)
  let mask1 = append_int_const(out, block, 0x5555555555555555L)
  let half = append_int_shift(out, block, input, Virtual(one))
  let half_masked = append_int_binop(
    out,
    block,
    IntAnd,
    Virtual(half),
    Virtual(mask1),
  )
  let step1 = append_int_binop(out, block, IntSub, input, Virtual(half_masked))

  let two = append_int_const(out, block, 2L)
  let mask2 = append_int_const(out, block, 0x3333333333333333L)
  let low2 = append_int_binop(
    out,
    block,
    IntAnd,
    Virtual(step1),
    Virtual(mask2),
  )
  let shifted2 = append_int_shift(out, block, Virtual(step1), Virtual(two))
  let high2 = append_int_binop(
    out,
    block,
    IntAnd,
    Virtual(shifted2),
    Virtual(mask2),
  )
  let step2 = append_int_binop(
    out,
    block,
    IntAdd,
    Virtual(low2),
    Virtual(high2),
  )

  let four = append_int_const(out, block, 4L)
  let mask4 = append_int_const(out, block, 0x0f0f0f0f0f0f0f0fL)
  let shifted4 = append_int_shift(out, block, Virtual(step2), Virtual(four))
  let sum4 = append_int_binop(
    out,
    block,
    IntAdd,
    Virtual(step2),
    Virtual(shifted4),
  )
  let step3 = append_int_binop(
    out,
    block,
    IntAnd,
    Virtual(sum4),
    Virtual(mask4),
  )

  let byte_sum = append_int_const(out, block, 0x0101010101010101L)
  let product = append_int_binop(
    out,
    block,
    IntMul,
    Virtual(step3),
    Virtual(byte_sum),
  )
  let final_shift = append_int_const(
    out,
    block,
    if inst.args[0].ty == I32 {
      24L
    } else {
      56L
    },
  )
  let result = append_int_shift(
    out,
    block,
    Virtual(product),
    Virtual(final_shift),
  )
  append_int_move_result(block, out, Virtual(result), inst.results)
}

///|
fn lower_int_mul_high(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
  signed : Bool,
) -> Unit {
  let lhs_tmp = out.new_vreg(Int)
  let rhs_tmp = out.new_vreg(Int)
  let lhs_move = out.new_inst(Move)
  lhs_move.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
  lhs_move.add_operand(@machv.Operand::def(Virtual(lhs_tmp)))
  block.append(lhs_move)
  let rhs_move = out.new_inst(Move)
  rhs_move.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[1])))
  rhs_move.add_operand(@machv.Operand::def(Virtual(rhs_tmp)))
  block.append(rhs_move)

  let mul = out.new_inst(IntMulHigh(signed))
  mul.add_operand(@machv.Operand::use_reg(Virtual(lhs_tmp)))
  mul.add_operand(@machv.Operand::use_reg(Virtual(rhs_tmp)))
  let rdx_tmp = out.new_vreg(Int)
  mul.add_operand(@machv.Operand::def(Virtual(rdx_tmp)))
  // TODO(x64_target): make the RAX low-result side effect a first-class MachV
  // tied/clobber operand once regalloc models clobbers during live ranges.
  mul.add_operand(@machv.Operand::def(Virtual(lhs_tmp)))
  add_fixed_constraint(mul, 0, int_reg(0))
  add_fixed_constraint(mul, 1, int_reg(8))
  add_fixed_constraint(mul, 2, int_reg(3))
  add_fixed_constraint(mul, 3, int_reg(0))
  block.append(mul)
  let result_move = out.new_inst(Move)
  result_move.add_operand(@machv.Operand::use_reg(Virtual(rdx_tmp)))
  add_defs(result_move, inst.results)
  block.append(result_move)
}

///|
fn lower_int_shift(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
  opcode : @machv.Opcode,
) -> Unit {
  let value_tmp = out.new_vreg(Int)
  let count_tmp = out.new_vreg(Int)
  let value_move = out.new_inst(Move)
  value_move.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
  value_move.add_operand(@machv.Operand::def(Virtual(value_tmp)))
  block.append(value_move)
  let count_move = out.new_inst(Move)
  count_move.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[1])))
  count_move.add_operand(@machv.Operand::def(Virtual(count_tmp)))
  block.append(count_move)

  let shift = out.new_inst(opcode)
  shift.add_operand(@machv.Operand::use_reg(Virtual(value_tmp)))
  shift.add_operand(@machv.Operand::use_reg(Virtual(count_tmp)))
  shift.add_operand(@machv.Operand::def(Virtual(value_tmp)))
  add_fixed_constraint(shift, 1, int_reg(1))
  block.append(shift)
  let result_move = out.new_inst(Move)
  result_move.add_operand(@machv.Operand::use_reg(Virtual(value_tmp)))
  add_defs(result_move, inst.results)
  block.append(result_move)
}

///|
fn lower_fconst(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
  value : Double,
) -> Unit {
  guard inst.results.length() == 1 else { return }
  let bits = match inst.results[0].ty {
    F32 => value.reinterpret_as_int64() & 0xffffffffL
    F64 => value.reinterpret_as_int64()
    _ => abort("x64_target: fconst result must be f32 or f64")
  }
  let raw = out.new_vreg(Int)
  let load = out.new_inst(IntConst(bits))
  load.add_operand(@machv.Operand::def(Virtual(raw)))
  block.append(load)
  let cast = out.new_inst(Bitcast)
  cast.add_operand(@machv.Operand::use_reg(Virtual(raw)))
  add_defs(cast, inst.results)
  block.append(cast)
}

///|
fn lower_fcmp(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
  cc : @milkir.FloatCC,
) -> Unit {
  let lowered = out.new_inst(FloatCmp(floatcc_to_machv(cc)))
  add_uses(lowered, inst.args)
  add_defs(lowered, inst.results)
  match cc {
    Eq | Ne => {
      // TODO(x64_target): replace this fixed allocatable scratch with a
      // first-class MachV temporary/clobber model once regalloc can reserve
      // per-instruction temps.
      let scratch = out.new_vreg(Int)
      lowered.add_operand(@machv.Operand::use_def(Virtual(scratch)))
      add_fixed_constraint(lowered, lowered.operands.length() - 1, int_reg(9))
    }
    Lt | Le | Gt | Ge => ()
  }
  block.append(lowered)
}

///|
fn lower_float_select(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
) -> Bool {
  guard inst.args.length() == 3 && inst.results.length() == 1 else {
    return false
  }
  match inst.results[0].ty {
    F32 | F64 => {
      let true_bits = out.new_vreg(Int)
      let false_bits = out.new_vreg(Int)
      let selected_bits = out.new_vreg(Int)
      let true_cast = out.new_inst(Bitcast)
      true_cast.add_operand(
        @machv.Operand::use_reg(reg_for_value(inst.args[1])),
      )
      true_cast.add_operand(@machv.Operand::def(Virtual(true_bits)))
      block.append(true_cast)
      let false_cast = out.new_inst(Bitcast)
      false_cast.add_operand(
        @machv.Operand::use_reg(reg_for_value(inst.args[2])),
      )
      false_cast.add_operand(@machv.Operand::def(Virtual(false_bits)))
      block.append(false_cast)
      let select = out.new_inst(Select)
      select.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
      select.add_operand(@machv.Operand::use_reg(Virtual(true_bits)))
      select.add_operand(@machv.Operand::use_reg(Virtual(false_bits)))
      select.add_operand(@machv.Operand::def(Virtual(selected_bits)))
      block.append(select)
      let result_cast = out.new_inst(Bitcast)
      result_cast.add_operand(@machv.Operand::use_reg(Virtual(selected_bits)))
      add_defs(result_cast, inst.results)
      block.append(result_cast)
      true
    }
    _ => false
  }
}

///|
fn load_mem_type(inst : @milkir.Inst) -> @machv.MemType {
  guard inst.results.length() == 1 else { return MemI64 }
  mem_type_for_type(inst.results[0].ty)
}

///|
fn store_mem_type(inst : @milkir.Inst) -> @machv.MemType {
  guard inst.args.length() >= 2 else { return MemI64 }
  mem_type_for_type(inst.args[1].ty)
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
    Load => LoadMemory(MemI64, 0)
    Store => StoreMemory(MemI64, 0)
    LoadPtr(ty) => LoadPtr(mem_type_for_type(ty), 0)
    StorePtr(ty) => StorePtr(mem_type_for_type(ty), 0)
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
  func : @milkir.Function,
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
) -> Unit {
  match inst.opcode {
    Sdiv => {
      lower_int_div(out, block, inst, true)
      return
    }
    Udiv => {
      lower_int_div(out, block, inst, false)
      return
    }
    Srem => {
      lower_int_rem(out, block, inst, true)
      return
    }
    Urem => {
      lower_int_rem(out, block, inst, false)
      return
    }
    Popcnt => {
      lower_int_popcnt(out, block, inst)
      return
    }
    Smulh => {
      lower_int_mul_high(out, block, inst, true)
      return
    }
    Umulh => {
      lower_int_mul_high(out, block, inst, false)
      return
    }
    Ishl => {
      lower_int_shift(out, block, inst, IntShl)
      return
    }
    Sshr => {
      lower_int_shift(out, block, inst, IntShr(true))
      return
    }
    Ushr => {
      lower_int_shift(out, block, inst, IntShr(false))
      return
    }
    Rotl => {
      lower_int_shift(out, block, inst, IntRotl)
      return
    }
    Rotr => {
      lower_int_shift(out, block, inst, IntRotr)
      return
    }
    Fconst(value) => {
      lower_fconst(out, block, inst, value)
      return
    }
    Fcmp(cc) => {
      lower_fcmp(out, block, inst, cc)
      return
    }
    Select => if lower_float_select(out, block, inst) { return }
    _ => ()
  }
  let lowered = match inst.opcode {
    LoadPtr(ty) => {
      let offset = const_offset_arg(func, inst.args, 1)
      out.new_inst(LoadPtr(mem_type_for_type(ty), offset))
    }
    StorePtr(ty) => {
      let offset = const_offset_arg(func, inst.args, 2)
      out.new_inst(StorePtr(mem_type_for_type(ty), offset))
    }
    Load => out.new_inst(LoadMemory(load_mem_type(inst), 0))
    Store => out.new_inst(StoreMemory(store_mem_type(inst), 0))
    _ => out.new_inst(opcode_for(inst.opcode))
  }
  match inst.opcode {
    LoadPtr(_) => {
      if inst.args.length() > 0 {
        lowered.add_operand(
          @machv.Operand::use_reg(reg_for_value(inst.args[0])),
        )
      }
      if inst.args.length() > 1 && find_iconst(func, inst.args[1]) is None {
        // TODO(x64_target): lower non-constant pointer offsets to scaled
        // reg-offset addressing instead of keeping the offset as a generic use.
        lowered.add_operand(
          @machv.Operand::use_reg(reg_for_value(inst.args[1])),
        )
      }
      add_defs(lowered, inst.results)
    }
    StorePtr(_) => {
      if inst.args.length() > 0 {
        lowered.add_operand(
          @machv.Operand::use_reg(reg_for_value(inst.args[0])),
        )
      }
      if inst.args.length() > 1 {
        lowered.add_operand(
          @machv.Operand::use_reg(reg_for_value(inst.args[1])),
        )
      }
      if inst.args.length() > 2 && find_iconst(func, inst.args[2]) is None {
        // TODO(x64_target): lower non-constant pointer offsets to scaled
        // reg-offset addressing instead of keeping the offset as a generic use.
        lowered.add_operand(
          @machv.Operand::use_reg(reg_for_value(inst.args[2])),
        )
      }
      add_defs(lowered, inst.results)
    }
    _ => {
      add_uses(lowered, inst.args)
      add_defs(lowered, inst.results)
      if inst.opcode is Call(_) {
        add_call_abi_constraints(lowered, inst.args, inst.results)
      } else if inst.opcode is CallPtr(_, _) || inst.opcode is CallIndirect(_) {
        // TODO(x64_target): split generic indirect-call ABI from Wasmoon-specific
        // callee VMContext and function-pointer placement.
      }
    }
  }
  // TODO(x64_target): expand selected x64 machine operations, target
  // constraints, and legalization for non-trivial memory ops.
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
  out.next_vreg_id = func.next_value_id
  for slot in func.stack_slots {
    out.new_stack_slot(slot.size, slot.align) |> ignore
  }
  for milk_block in func.blocks {
    let block = out.new_block()
    for inst in milk_block.instructions {
      lower_inst(func, out, block, inst)
    }
    if milk_block.terminator is Some(terminator) {
      lower_terminator(block, terminator)
    }
  }
  out
}
