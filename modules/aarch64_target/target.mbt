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
  // TODO(aarch64_target): materialize overflow stack arguments once MachV
  // carries outgoing stack-argument effects in a target-independent form.
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
fn lower_int_rem(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
  signed : Bool,
) -> Unit {
  // TODO(aarch64_target): lower i64 remainder to SDIV/UDIV + MSUB once MachV
  // has a structured fused multiply-subtract opcode. This correctness-first
  // expansion intentionally uses generic MachV arithmetic today.
  let quotient = out.new_vreg(Int)
  let product = out.new_vreg(Int)
  let div = out.new_inst(IntDiv(signed))
  div.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
  div.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[1])))
  div.add_operand(@machv.Operand::def(Virtual(quotient)))
  block.append(div)
  let mul = out.new_inst(IntMul)
  mul.add_operand(@machv.Operand::use_reg(Virtual(quotient)))
  mul.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[1])))
  mul.add_operand(@machv.Operand::def(Virtual(product)))
  block.append(mul)
  let sub = out.new_inst(IntSub)
  sub.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
  sub.add_operand(@machv.Operand::use_reg(Virtual(product)))
  add_defs(sub, inst.results)
  block.append(sub)
}

///|
fn lower_int_rotl(
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
) -> Unit {
  // TODO(aarch64_target): make rotate-left a target combine once MachV has
  // explicit value-width metadata. AArch64 variable rotate masks the count, so
  // rotl(x, n) is encoded as rorv(x, 0 - n) for the current 64-bit path.
  let zero = out.new_vreg(Int)
  let neg_count = out.new_vreg(Int)
  let zero_const = out.new_inst(IntConst(0L))
  zero_const.add_operand(@machv.Operand::def(Virtual(zero)))
  block.append(zero_const)
  let negate = out.new_inst(IntSub)
  negate.add_operand(@machv.Operand::use_reg(Virtual(zero)))
  negate.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[1])))
  negate.add_operand(@machv.Operand::def(Virtual(neg_count)))
  block.append(negate)
  let rotr = out.new_inst(IntRotr)
  rotr.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
  rotr.add_operand(@machv.Operand::use_reg(Virtual(neg_count)))
  add_defs(rotr, inst.results)
  block.append(rotr)
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
    _ => abort("aarch64_target: fconst result must be f32 or f64")
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
fn lower_inst(
  func : @milkir.Function,
  out : @machv.Function,
  block : @machv.Block,
  inst : @milkir.Inst,
) -> Unit {
  match inst.opcode {
    Srem => {
      lower_int_rem(out, block, inst, true)
      return
    }
    Urem => {
      lower_int_rem(out, block, inst, false)
      return
    }
    Rotl => {
      lower_int_rotl(out, block, inst)
      return
    }
    Fconst(value) => {
      lower_fconst(out, block, inst, value)
      return
    }
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
        // TODO(aarch64_target): lower non-constant pointer offsets to extended
        // register-offset addressing instead of keeping the offset as a generic use.
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
        // TODO(aarch64_target): lower non-constant pointer offsets to extended
        // register-offset addressing instead of keeping the offset as a generic use.
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
        // TODO(aarch64_target): split generic indirect-call ABI from Wasmoon-specific
        // callee VMContext and function-pointer placement.
      }
    }
  }
  // TODO(aarch64_target): expand selected AArch64 machine operations, target
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
