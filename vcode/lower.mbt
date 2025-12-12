// IR to VCode Lowering
// Converts high-level SSA IR to low-level VCode representation
//
// This is the instruction selection phase that:
// 1. Maps IR values to virtual registers
// 2. Converts IR opcodes to VCode opcodes
// 3. Handles control flow translation
// 4. Performs pattern matching for AArch64-specific instructions

///|
/// Lowering context - tracks state during IR to VCode conversion
pub(all) struct LoweringContext {
  ir_func : @ir.Function
  vcode_func : VCodeFunction
  // Map from IR Value id to VReg
  value_map : Map[Int, VReg]
  // Map from IR Block id to VCode block id
  block_map : Map[Int, Int]
  // Map from IR Value id to stack param index (for params >= 8)
  stack_param_map : Map[Int, (Int, RegClass)]
}

///|
pub fn LoweringContext::new(ir_func : @ir.Function) -> LoweringContext {
  {
    ir_func,
    vcode_func: VCodeFunction::new(ir_func.name),
    value_map: {},
    block_map: {},
    stack_param_map: {},
  }
}

///|
/// Get or create a VReg for an IR Value
fn LoweringContext::get_vreg(self : LoweringContext, value : @ir.Value) -> VReg {
  match self.value_map.get(value.id) {
    Some(vreg) => vreg
    None => {
      let class = ir_type_to_reg_class(value.ty)
      let vreg = self.vcode_func.new_vreg(class)
      self.value_map.set(value.id, vreg)
      vreg
    }
  }
}

///|
/// Get VReg for an IR Value, generating LoadStackParam if it's a stack parameter
/// This should be used when lowering instructions that use values
fn LoweringContext::get_vreg_for_use(
  self : LoweringContext,
  value : @ir.Value,
  block : VCodeBlock,
) -> VReg {
  // First check if it's a stack parameter
  match self.stack_param_map.get(value.id) {
    Some((param_idx, class)) => {
      // Generate LoadStackParam instruction
      let result = self.vcode_func.new_vreg(class)
      let inst = VCodeInst::new(LoadStackParam(param_idx, class))
      inst.add_def({ reg: Virtual(result) })
      block.add_inst(inst)
      result
    }
    None =>
      // Not a stack param, use normal get_vreg
      self.get_vreg(value)
  }
}

///|
/// Create a new VReg with the given class
#warnings("-unused_value")
fn LoweringContext::new_vreg(self : LoweringContext, class : RegClass) -> VReg {
  self.vcode_func.new_vreg(class)
}

///|
/// Get VCode block id for an IR block id
fn LoweringContext::get_block_id(
  self : LoweringContext,
  ir_block_id : Int,
) -> Int {
  match self.block_map.get(ir_block_id) {
    Some(id) => id
    None => panic()
  }
}

///|
/// Convert IR Type to RegClass
fn ir_type_to_reg_class(ty : @ir.Type) -> RegClass {
  match ty {
    @ir.Type::I32 | @ir.Type::I64 | @ir.Type::FuncRef | @ir.Type::ExternRef =>
      Int
    @ir.Type::F32 => Float32
    @ir.Type::F64 => Float64
  }
}

///|
/// Convert IR Type to MemType
fn ir_type_to_mem_type(ty : @ir.Type) -> MemType {
  match ty {
    @ir.Type::I32 => I32
    @ir.Type::I64 => I64
    @ir.Type::F32 => F32
    @ir.Type::F64 => F64
    _ => I32 // Fallback
  }
}

// ============ Pattern Matching Helpers for AArch64 Instruction Selection ============

///|
/// Check if a value is defined by a shift-left instruction with a constant
/// Returns (shifted_value, shift_amount) if matched
fn match_shl_const_value(
  ctx : LoweringContext,
  value : @ir.Value,
) -> (@ir.Value, Int)? {
  match find_defining_inst(ctx, value) {
    Some(inst) =>
      if inst.opcode is @ir.Opcode::Ishl {
        // Check if shift amount is a constant
        let shift_operand = inst.operands[1]
        match find_defining_inst(ctx, shift_operand) {
          Some(shift_inst) =>
            if shift_inst.opcode is @ir.Opcode::Iconst(amount) {
              let shift_val = amount.to_int()
              if shift_val >= 0 && shift_val <= 63 {
                return Some((inst.operands[0], shift_val))
              }
            }
          None => ()
        }
      }
    None => ()
  }
  None
}

///|
/// Check if a value is defined by a multiply instruction
/// Returns (lhs, rhs) if matched
fn match_mul_value(
  ctx : LoweringContext,
  value : @ir.Value,
) -> (@ir.Value, @ir.Value)? {
  match find_defining_inst(ctx, value) {
    Some(inst) =>
      if inst.opcode is @ir.Opcode::Imul {
        return Some((inst.operands[0], inst.operands[1]))
      }
    None => ()
  }
  None
}

///|
/// Check if a value is the constant 0
fn is_const_zero_value(ctx : LoweringContext, value : @ir.Value) -> Bool {
  match find_defining_inst(ctx, value) {
    Some(inst) => if inst.opcode is @ir.Opcode::Iconst(val) { return val == 0L }
    None => ()
  }
  false
}

///|
/// Lower an entire IR function to VCode
pub fn lower_function(ir_func : @ir.Function) -> VCodeFunction {
  let ctx = LoweringContext::new(ir_func)

  // Phase 1: Create VCode blocks and set up block mapping
  for ir_block in ir_func.blocks {
    let vcode_block = ctx.vcode_func.new_block()
    ctx.block_map.set(ir_block.id, vcode_block.id)
  }

  // Phase 2: Lower function parameters
  // Only the first 8 parameters are passed in registers (X3-X10)
  // Parameters 8+ are passed on the stack and loaded on demand
  let max_reg_params = 8
  for i, param in ir_func.params {
    let (value, ty) = param
    let class = ir_type_to_reg_class(ty)
    if i < max_reg_params {
      // Register parameter: allocate VReg
      let vreg = ctx.vcode_func.add_param(class)
      ctx.value_map.set(value.id, vreg)
    } else {
      // Stack parameter: record in stack_param_map for on-demand loading
      ctx.stack_param_map.set(value.id, (i, class))
    }
  }

  // Phase 3: Lower result types
  for ty in ir_func.results {
    let class = ir_type_to_reg_class(ty)
    ctx.vcode_func.add_result(class)
    ctx.vcode_func.add_result_type(ty) // Also store full type info
  }

  // Phase 3.5: Pre-register all block parameters
  // This is critical: when processing jumps/branches, we need to know
  // the vreg IDs of target block parameters BEFORE lowering those blocks.
  for i, ir_block in ir_func.blocks {
    for param in ir_block.params {
      let (value, ty) = param
      let class = ir_type_to_reg_class(ty)
      let vreg = ctx.vcode_func.new_vreg(class)
      ctx.value_map.set(value.id, vreg)
      ctx.vcode_func.blocks[i].params.push(vreg)
    }
  }

  // Phase 4: Lower each block (instructions and terminators only, params already done)
  for i, ir_block in ir_func.blocks {
    lower_block_body(ctx, ir_block, ctx.vcode_func.blocks[i])
  }
  ctx.vcode_func
}

///|
/// Lower a single IR block to VCode (body only, params handled in pre-registration)
fn lower_block_body(
  ctx : LoweringContext,
  ir_block : @ir.Block,
  vcode_block : VCodeBlock,
) -> Unit {
  // Block parameters are already handled in pre-registration phase

  // Lower instructions
  for inst in ir_block.instructions {
    lower_inst(ctx, inst, vcode_block)
  }

  // Lower terminator
  match ir_block.terminator {
    Some(term) => lower_terminator(ctx, term, vcode_block)
    None => ()
  }
}

///|
/// Lower a single IR instruction to VCode
fn lower_inst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.opcode {
    // Constants
    @ir.Opcode::Iconst(val) => lower_iconst(ctx, inst, block, val)
    @ir.Opcode::Fconst(val) => lower_fconst(ctx, inst, block, val)

    // Integer arithmetic - with pattern matching for AArch64
    @ir.Opcode::Iadd => lower_iadd(ctx, inst, block)
    @ir.Opcode::Isub => lower_isub(ctx, inst, block)
    @ir.Opcode::Imul => lower_binary_int(ctx, inst, block, Mul)
    @ir.Opcode::Sdiv => lower_binary_int(ctx, inst, block, SDiv)
    @ir.Opcode::Udiv => lower_binary_int(ctx, inst, block, UDiv)
    @ir.Opcode::Srem => lower_rem(ctx, inst, block, true)
    @ir.Opcode::Urem => lower_rem(ctx, inst, block, false)

    // Bitwise operations - with pattern matching for shifted operands
    @ir.Opcode::Band => lower_band(ctx, inst, block)
    @ir.Opcode::Bor => lower_bor(ctx, inst, block)
    @ir.Opcode::Bxor => lower_bxor(ctx, inst, block)
    @ir.Opcode::Ishl => lower_binary_int(ctx, inst, block, Shl)
    @ir.Opcode::Sshr => lower_binary_int(ctx, inst, block, AShr)
    @ir.Opcode::Ushr => lower_binary_int(ctx, inst, block, LShr)
    @ir.Opcode::Rotl => lower_binary_int(ctx, inst, block, Rotl)
    @ir.Opcode::Rotr => lower_binary_int(ctx, inst, block, Rotr)
    @ir.Opcode::Bnot => lower_unary_int(ctx, inst, block, Not)

    // Integer comparisons
    @ir.Opcode::Icmp(cc) => lower_icmp(ctx, inst, block, cc)

    // Floating point arithmetic
    @ir.Opcode::Fadd => lower_binary_float(ctx, inst, block)
    @ir.Opcode::Fsub => lower_binary_float(ctx, inst, block)
    @ir.Opcode::Fmul => lower_binary_float(ctx, inst, block)
    @ir.Opcode::Fdiv => lower_binary_float(ctx, inst, block)
    @ir.Opcode::Fmin => lower_binary_float(ctx, inst, block)
    @ir.Opcode::Fmax => lower_binary_float(ctx, inst, block)

    // Floating point unary operations
    @ir.Opcode::Fsqrt => lower_unary_float(ctx, inst, block)
    @ir.Opcode::Fabs => lower_unary_float(ctx, inst, block)
    @ir.Opcode::Fneg => lower_unary_float(ctx, inst, block)
    @ir.Opcode::Fceil => lower_unary_float(ctx, inst, block)
    @ir.Opcode::Ffloor => lower_unary_float(ctx, inst, block)
    @ir.Opcode::Ftrunc => lower_unary_float(ctx, inst, block)
    @ir.Opcode::Fnearest => lower_unary_float(ctx, inst, block)

    // Bit counting operations
    @ir.Opcode::Clz => lower_unary_int(ctx, inst, block, Clz)
    @ir.Opcode::Ctz => lower_unary_int(ctx, inst, block, Ctz)
    @ir.Opcode::Popcnt => lower_unary_int(ctx, inst, block, Popcnt)

    // Floating point comparisons
    @ir.Opcode::Fcmp(cc) => lower_fcmp(ctx, inst, block, cc)

    // Memory operations
    @ir.Opcode::Load(ty, offset) => lower_load(ctx, inst, block, ty, offset)
    @ir.Opcode::Store(ty, offset) => lower_store(ctx, inst, block, ty, offset)

    // Narrow memory operations (8/16/32-bit with sign/zero extension)
    @ir.Opcode::Load8S(_ty, offset) =>
      lower_load_narrow(ctx, inst, block, offset, fn(o) { Load8S(o) })
    @ir.Opcode::Load8U(_ty, offset) =>
      lower_load_narrow(ctx, inst, block, offset, fn(o) { Load8U(o) })
    @ir.Opcode::Load16S(_ty, offset) =>
      lower_load_narrow(ctx, inst, block, offset, fn(o) { Load16S(o) })
    @ir.Opcode::Load16U(_ty, offset) =>
      lower_load_narrow(ctx, inst, block, offset, fn(o) { Load16U(o) })
    @ir.Opcode::Load32S(offset) =>
      lower_load_narrow(ctx, inst, block, offset, fn(o) { Load32S(o) })
    @ir.Opcode::Load32U(offset) =>
      lower_load_narrow(ctx, inst, block, offset, fn(o) { Load32U(o) })
    @ir.Opcode::Store8(offset) =>
      lower_store_narrow(ctx, inst, block, offset, I8)
    @ir.Opcode::Store16(offset) =>
      lower_store_narrow(ctx, inst, block, offset, I16)
    @ir.Opcode::Store32(offset) =>
      lower_store_narrow(ctx, inst, block, offset, I32)

    // Conversions
    @ir.Opcode::Sextend => lower_extend(ctx, inst, block, signed=true)
    @ir.Opcode::Uextend => lower_extend(ctx, inst, block, signed=false)
    @ir.Opcode::Ireduce => lower_truncate(ctx, inst, block)
    @ir.Opcode::FcvtToSint => lower_float_to_int(ctx, inst, block, signed=true)
    @ir.Opcode::FcvtToUint => lower_float_to_int(ctx, inst, block, signed=false)
    @ir.Opcode::SintToFcvt => lower_int_to_float(ctx, inst, block, signed=true)
    @ir.Opcode::UintToFcvt => lower_int_to_float(ctx, inst, block, signed=false)
    @ir.Opcode::Fpromote => lower_promote(ctx, inst, block)
    @ir.Opcode::Fdemote => lower_demote(ctx, inst, block)
    @ir.Opcode::Bitcast => lower_bitcast(ctx, inst, block)

    // Misc
    @ir.Opcode::Copy => lower_copy(ctx, inst, block)
    @ir.Opcode::Select => lower_select(ctx, inst, block)

    // Memory management
    @ir.Opcode::MemoryGrow => lower_memory_grow(ctx, inst, block)
    @ir.Opcode::MemorySize => lower_memory_size(ctx, inst, block)

    // Function calls
    @ir.Opcode::Call(func_idx) => lower_call(ctx, inst, block, func_idx)
    @ir.Opcode::CallIndirect(_type_idx) => lower_call_indirect(ctx, inst, block)
  }
}

///|
/// Lower integer constant
fn lower_iconst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  val : Int64,
) -> Unit {
  match inst.result {
    Some(result) => {
      let vreg = ctx.get_vreg(result)
      let vcode_inst = VCodeInst::new(LoadConst(val))
      vcode_inst.add_def({ reg: Virtual(vreg) })
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower float constant
fn lower_fconst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  val : Double,
) -> Unit {
  match inst.result {
    Some(result) => {
      let vreg = ctx.get_vreg(result)
      // Determine if this is an F32 or F64 constant based on the result type
      let opcode = match result.ty {
        @ir.Type::F32 => {
          // Convert Double to Float, then get its 32-bit representation
          let float_val = Float::from_double(val)
          let bits = float_val.reinterpret_as_int()
          LoadConstF32(bits)
        }
        _ => {
          // F64: get 64-bit representation
          let bits = val.reinterpret_as_int64()
          LoadConstF64(bits)
        }
      }
      let vcode_inst = VCodeInst::new(opcode)
      vcode_inst.add_def({ reg: Virtual(vreg) })
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower binary integer operation
fn lower_binary_int(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  opcode : VCodeOpcode,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
      let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
      let vcode_inst = VCodeInst::new(opcode)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(lhs))
      vcode_inst.add_use(Virtual(rhs))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

// ============ AArch64-Specific Lowering with Pattern Matching ============

///|
/// Lower integer add with pattern matching for MADD and shifted operands
/// Patterns:
/// - add(x, mul(y, z)) -> MADD: x + y * z
/// - add(mul(x, y), z) -> MADD: z + x * y (commutative)
/// - add(x, shl(y, n)) -> AddShifted: x + (y << n)
/// - add(shl(x, n), y) -> AddShifted: y + (x << n) (commutative)
fn lower_iadd(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: add(x, mul(y, z)) -> MADD
  match match_mul_value(ctx, rhs_val) {
    Some((mul_lhs, mul_rhs)) => {
      let acc = ctx.get_vreg_for_use(lhs_val, block)
      let src1 = ctx.get_vreg_for_use(mul_lhs, block)
      let src2 = ctx.get_vreg_for_use(mul_rhs, block)
      let vcode_inst = VCodeInst::new(Madd)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(acc)) // accumulator
      vcode_inst.add_use(Virtual(src1)) // multiplicand
      vcode_inst.add_use(Virtual(src2)) // multiplier
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Pattern: add(mul(x, y), z) -> MADD (commutative)
  match match_mul_value(ctx, lhs_val) {
    Some((mul_lhs, mul_rhs)) => {
      let acc = ctx.get_vreg_for_use(rhs_val, block)
      let src1 = ctx.get_vreg_for_use(mul_lhs, block)
      let src2 = ctx.get_vreg_for_use(mul_rhs, block)
      let vcode_inst = VCodeInst::new(Madd)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(acc))
      vcode_inst.add_use(Virtual(src1))
      vcode_inst.add_use(Virtual(src2))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Pattern: add(x, shl(y, n)) -> AddShifted
  match match_shl_const_value(ctx, rhs_val) {
    Some((shifted, amount)) => {
      let rn = ctx.get_vreg_for_use(lhs_val, block)
      let rm = ctx.get_vreg_for_use(shifted, block)
      let vcode_inst = VCodeInst::new(AddShifted(Lsl, amount))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(rn))
      vcode_inst.add_use(Virtual(rm))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Pattern: add(shl(x, n), y) -> AddShifted (commutative)
  match match_shl_const_value(ctx, lhs_val) {
    Some((shifted, amount)) => {
      let rn = ctx.get_vreg_for_use(rhs_val, block)
      let rm = ctx.get_vreg_for_use(shifted, block)
      let vcode_inst = VCodeInst::new(AddShifted(Lsl, amount))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(rn))
      vcode_inst.add_use(Virtual(rm))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Default: regular add
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = VCodeInst::new(Add)
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower integer sub with pattern matching for MSUB, MNEG, and shifted operands
/// Patterns:
/// - sub(x, mul(y, z)) -> MSUB: x - y * z
/// - sub(0, mul(x, y)) -> MNEG: -(x * y)
/// - sub(x, shl(y, n)) -> SubShifted: x - (y << n)
fn lower_isub(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: sub(0, mul(x, y)) -> MNEG
  if is_const_zero_value(ctx, lhs_val) {
    match match_mul_value(ctx, rhs_val) {
      Some((mul_lhs, mul_rhs)) => {
        let src1 = ctx.get_vreg_for_use(mul_lhs, block)
        let src2 = ctx.get_vreg_for_use(mul_rhs, block)
        let vcode_inst = VCodeInst::new(Mneg)
        vcode_inst.add_def({ reg: Virtual(dst) })
        vcode_inst.add_use(Virtual(src1))
        vcode_inst.add_use(Virtual(src2))
        block.add_inst(vcode_inst)
        return
      }
      None => ()
    }
  }

  // Pattern: sub(x, mul(y, z)) -> MSUB
  match match_mul_value(ctx, rhs_val) {
    Some((mul_lhs, mul_rhs)) => {
      let acc = ctx.get_vreg_for_use(lhs_val, block)
      let src1 = ctx.get_vreg_for_use(mul_lhs, block)
      let src2 = ctx.get_vreg_for_use(mul_rhs, block)
      let vcode_inst = VCodeInst::new(Msub)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(acc))
      vcode_inst.add_use(Virtual(src1))
      vcode_inst.add_use(Virtual(src2))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Pattern: sub(x, shl(y, n)) -> SubShifted
  match match_shl_const_value(ctx, rhs_val) {
    Some((shifted, amount)) => {
      let rn = ctx.get_vreg_for_use(lhs_val, block)
      let rm = ctx.get_vreg_for_use(shifted, block)
      let vcode_inst = VCodeInst::new(SubShifted(Lsl, amount))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(rn))
      vcode_inst.add_use(Virtual(rm))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Default: regular sub
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = VCodeInst::new(Sub)
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower bitwise AND with pattern matching for shifted operands
fn lower_band(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: and(x, shl(y, n)) -> AndShifted
  match match_shl_const_value(ctx, rhs_val) {
    Some((shifted, amount)) => {
      let rn = ctx.get_vreg_for_use(lhs_val, block)
      let rm = ctx.get_vreg_for_use(shifted, block)
      let vcode_inst = VCodeInst::new(AndShifted(Lsl, amount))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(rn))
      vcode_inst.add_use(Virtual(rm))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Pattern: and(shl(x, n), y) -> AndShifted (commutative)
  match match_shl_const_value(ctx, lhs_val) {
    Some((shifted, amount)) => {
      let rn = ctx.get_vreg_for_use(rhs_val, block)
      let rm = ctx.get_vreg_for_use(shifted, block)
      let vcode_inst = VCodeInst::new(AndShifted(Lsl, amount))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(rn))
      vcode_inst.add_use(Virtual(rm))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Default: regular and
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = VCodeInst::new(And)
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower bitwise OR with pattern matching for shifted operands
fn lower_bor(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: or(x, shl(y, n)) -> OrShifted
  match match_shl_const_value(ctx, rhs_val) {
    Some((shifted, amount)) => {
      let rn = ctx.get_vreg_for_use(lhs_val, block)
      let rm = ctx.get_vreg_for_use(shifted, block)
      let vcode_inst = VCodeInst::new(OrShifted(Lsl, amount))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(rn))
      vcode_inst.add_use(Virtual(rm))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Pattern: or(shl(x, n), y) -> OrShifted (commutative)
  match match_shl_const_value(ctx, lhs_val) {
    Some((shifted, amount)) => {
      let rn = ctx.get_vreg_for_use(rhs_val, block)
      let rm = ctx.get_vreg_for_use(shifted, block)
      let vcode_inst = VCodeInst::new(OrShifted(Lsl, amount))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(rn))
      vcode_inst.add_use(Virtual(rm))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Default: regular or
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = VCodeInst::new(Or)
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower bitwise XOR with pattern matching for shifted operands
fn lower_bxor(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: xor(x, shl(y, n)) -> XorShifted
  match match_shl_const_value(ctx, rhs_val) {
    Some((shifted, amount)) => {
      let rn = ctx.get_vreg_for_use(lhs_val, block)
      let rm = ctx.get_vreg_for_use(shifted, block)
      let vcode_inst = VCodeInst::new(XorShifted(Lsl, amount))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(rn))
      vcode_inst.add_use(Virtual(rm))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Pattern: xor(shl(x, n), y) -> XorShifted (commutative)
  match match_shl_const_value(ctx, lhs_val) {
    Some((shifted, amount)) => {
      let rn = ctx.get_vreg_for_use(rhs_val, block)
      let rm = ctx.get_vreg_for_use(shifted, block)
      let vcode_inst = VCodeInst::new(XorShifted(Lsl, amount))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(rn))
      vcode_inst.add_use(Virtual(rm))
      block.add_inst(vcode_inst)
      return
    }
    None => ()
  }

  // Default: regular xor
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = VCodeInst::new(Xor)
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower binary float operation
fn lower_binary_float(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
      let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
      // Determine if this is f32 based on result type
      let is_f32 = result.ty is @ir.Type::F32
      // Select VCode opcode based on IR opcode
      let opcode : VCodeOpcode = match inst.opcode {
        @ir.Opcode::Fadd => FAdd(is_f32)
        @ir.Opcode::Fsub => FSub(is_f32)
        @ir.Opcode::Fmul => FMul(is_f32)
        @ir.Opcode::Fdiv => FDiv(is_f32)
        @ir.Opcode::Fmin => FMin(is_f32)
        @ir.Opcode::Fmax => FMax(is_f32)
        _ => FAdd(is_f32) // Fallback, should not happen
      }
      let vcode_inst = VCodeInst::new(opcode)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(lhs))
      vcode_inst.add_use(Virtual(rhs))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower floating-point unary operation (sqrt, abs, neg, ceil, floor, trunc, nearest, promote, demote)
fn lower_unary_float(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg_for_use(inst.operands[0], block)
      // Determine if this is f32 based on result type
      let is_f32 = result.ty is @ir.Type::F32
      // Select VCode opcode based on IR opcode
      let opcode : VCodeOpcode = match inst.opcode {
        @ir.Opcode::Fsqrt => FSqrt(is_f32)
        @ir.Opcode::Fabs => FAbs(is_f32)
        @ir.Opcode::Fneg => FNeg(is_f32)
        @ir.Opcode::Fceil => FCeil(is_f32)
        @ir.Opcode::Ffloor => FFloor(is_f32)
        @ir.Opcode::Ftrunc => FTrunc(is_f32)
        @ir.Opcode::Fnearest => FNearest(is_f32)
        _ => FSqrt(is_f32) // Fallback, should not happen
      }
      let vcode_inst = VCodeInst::new(opcode)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower f32 to f64 promotion
fn lower_promote(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg_for_use(inst.operands[0], block)
      let vcode_inst = VCodeInst::new(FPromote)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower f64 to f32 demotion
fn lower_demote(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg_for_use(inst.operands[0], block)
      let vcode_inst = VCodeInst::new(FDemote)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower integer unary operation (not)
fn lower_unary_int(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  opcode : VCodeOpcode,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg_for_use(inst.operands[0], block)
      let vcode_inst = VCodeInst::new(opcode)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower integer remainder: rem = a - (a / b) * b
/// AArch64 doesn't have a direct remainder instruction, so we use MSUB:
/// MSUB rd, rn, rm, ra computes: ra - rn * rm
/// For remainder: a - (a / b) * b = MSUB result, quotient, b, a
fn lower_rem(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  signed : Bool,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
      let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
      // Use SRem/URem VCode opcode which will be lowered to SDIV+MSUB or UDIV+MSUB
      let opcode = if signed { SRem } else { URem }
      let vcode_inst = VCodeInst::new(opcode)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(lhs))
      vcode_inst.add_use(Virtual(rhs))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower bitcast (reinterpret bits between int and float)
fn lower_bitcast(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg_for_use(inst.operands[0], block)
      let vcode_inst = VCodeInst::new(Bitcast)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Convert IR IntCC to VCode CmpKind
fn ir_intcc_to_cmp_kind(cc : @ir.IntCC) -> CmpKind {
  match cc {
    @ir.IntCC::Eq => Eq
    @ir.IntCC::Ne => Ne
    @ir.IntCC::Slt => Slt
    @ir.IntCC::Sle => Sle
    @ir.IntCC::Sgt => Sgt
    @ir.IntCC::Sge => Sge
    @ir.IntCC::Ult => Ult
    @ir.IntCC::Ule => Ule
    @ir.IntCC::Ugt => Ugt
    @ir.IntCC::Uge => Uge
  }
}

///|
/// Lower integer comparison
fn lower_icmp(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  cc : @ir.IntCC,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
      let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
      let kind = ir_intcc_to_cmp_kind(cc)
      let vcode_inst = VCodeInst::new(Cmp(kind))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(lhs))
      vcode_inst.add_use(Virtual(rhs))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Convert IR FloatCC to VCode FCmpKind
fn ir_floatcc_to_fcmp_kind(cc : @ir.FloatCC) -> FCmpKind {
  match cc {
    @ir.FloatCC::Eq => FCmpKind::Eq
    @ir.FloatCC::Ne => FCmpKind::Ne
    @ir.FloatCC::Lt => FCmpKind::Lt
    @ir.FloatCC::Le => FCmpKind::Le
    @ir.FloatCC::Gt => FCmpKind::Gt
    @ir.FloatCC::Ge => FCmpKind::Ge
  }
}

///|
/// Lower float comparison
fn lower_fcmp(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  cc : @ir.FloatCC,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
      let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
      let kind = ir_floatcc_to_fcmp_kind(cc)
      let vcode_inst = VCodeInst::new(FCmp(kind))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(lhs))
      vcode_inst.add_use(Virtual(rhs))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Get access size for a MemType
fn mem_type_size(ty : MemType) -> Int {
  match ty {
    I8 => 1
    I16 => 2
    I32 | F32 => 4
    I64 | F64 => 8
  }
}

///|
/// Emit bounds check instruction
/// Checks that wasm_addr + offset + access_size <= memory_size
fn emit_bounds_check(
  _ctx : LoweringContext,
  block : VCodeBlock,
  wasm_addr : VReg,
  offset : Int,
  access_size : Int,
) -> Unit {
  let bounds_check = VCodeInst::new(BoundsCheck(offset, access_size))
  bounds_check.add_use(Virtual(wasm_addr))
  block.add_inst(bounds_check)
}

///|
/// Lower load instruction
/// For WASM, addr is an offset within linear memory, so we need to add memory_base (X21)
fn lower_load(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  ty : @ir.Type,
  offset : Int,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let wasm_addr = ctx.get_vreg_for_use(inst.operands[0], block)
      // Determine access size for bounds check
      let mem_ty = ir_type_to_mem_type(ty)
      let access_size = mem_type_size(mem_ty)
      // Emit bounds check: trap if wasm_addr + offset + access_size > memory_size
      emit_bounds_check(ctx, block, wasm_addr, offset, access_size)
      // Compute effective address: memory_base (X21) + wasm_addr
      let effective_addr = ctx.vcode_func.new_vreg(Int)
      let add_inst = VCodeInst::new(Add)
      add_inst.add_def({ reg: Virtual(effective_addr) })
      add_inst.add_use(Physical({ index: 21, class: Int })) // X21 = memory_base
      add_inst.add_use(Virtual(wasm_addr))
      block.add_inst(add_inst)
      // Now load from effective_addr + offset
      // Check alignment requirement based on memory type
      let alignment = match mem_ty {
        I8 => 1
        I16 => 2
        I32 | F32 => 4
        I64 | F64 => 8
      }
      // If offset is not aligned or too large, add it to the address first
      if offset != 0 && (offset % alignment != 0 || offset > 4095 * alignment) {
        // Add offset to effective_addr using immediate add
        let addr_with_offset = ctx.vcode_func.new_vreg(Int)
        let offset_add = VCodeInst::new(AddImm(offset))
        offset_add.add_def({ reg: Virtual(addr_with_offset) })
        offset_add.add_use(Virtual(effective_addr))
        block.add_inst(offset_add)
        // Now load with offset=0
        let vcode_inst = VCodeInst::new(Load(mem_ty, 0))
        vcode_inst.add_def({ reg: Virtual(dst) })
        vcode_inst.add_use(Virtual(addr_with_offset))
        block.add_inst(vcode_inst)
      } else {
        // Offset can be encoded directly in the load instruction
        let vcode_inst = VCodeInst::new(Load(mem_ty, offset))
        vcode_inst.add_def({ reg: Virtual(dst) })
        vcode_inst.add_use(Virtual(effective_addr))
        block.add_inst(vcode_inst)
      }
    }
    None => ()
  }
}

///|
/// Lower store instruction
/// For WASM, addr is an offset within linear memory, so we need to add memory_base (X21)
fn lower_store(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  ty : @ir.Type,
  offset : Int,
) -> Unit {
  // Store has no result, just uses: addr, value
  let wasm_addr = ctx.get_vreg_for_use(inst.operands[0], block)
  let value = ctx.get_vreg_for_use(inst.operands[1], block)
  // Determine access size for bounds check
  let mem_ty = ir_type_to_mem_type(ty)
  let access_size = mem_type_size(mem_ty)
  // Emit bounds check: trap if wasm_addr + offset + access_size > memory_size
  emit_bounds_check(ctx, block, wasm_addr, offset, access_size)
  // Compute effective address: memory_base (X21) + wasm_addr
  let effective_addr = ctx.vcode_func.new_vreg(Int)
  let add_inst = VCodeInst::new(Add)
  add_inst.add_def({ reg: Virtual(effective_addr) })
  add_inst.add_use(Physical({ index: 21, class: Int })) // X21 = memory_base
  add_inst.add_use(Virtual(wasm_addr))
  block.add_inst(add_inst)
  // Now store to effective_addr + offset
  // Check alignment requirement based on memory type
  let alignment = match mem_ty {
    I8 => 1
    I16 => 2
    I32 | F32 => 4
    I64 | F64 => 8
  }
  // If offset is not aligned or too large, add it to the address first
  if offset != 0 && (offset % alignment != 0 || offset > 4095 * alignment) {
    // Add offset to effective_addr using immediate add
    let addr_with_offset = ctx.vcode_func.new_vreg(Int)
    let offset_add = VCodeInst::new(AddImm(offset))
    offset_add.add_def({ reg: Virtual(addr_with_offset) })
    offset_add.add_use(Virtual(effective_addr))
    block.add_inst(offset_add)
    // Now store with offset=0
    let vcode_inst = VCodeInst::new(Store(mem_ty, 0))
    vcode_inst.add_use(Virtual(addr_with_offset))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  } else {
    // Offset can be encoded directly in the store instruction
    let vcode_inst = VCodeInst::new(Store(mem_ty, offset))
    vcode_inst.add_use(Virtual(effective_addr))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower narrow load instruction (8/16/32-bit with sign/zero extension)
/// For WASM, addr is an offset within linear memory, so we need to add memory_base (X21)
fn lower_load_narrow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  offset : Int,
  opcode_fn : (Int) -> VCodeOpcode,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let wasm_addr = ctx.get_vreg_for_use(inst.operands[0], block)
      // Determine access size based on opcode type
      let sample_opcode = opcode_fn(0)
      let access_size = match sample_opcode {
        Load8S(_) | Load8U(_) => 1
        Load16S(_) | Load16U(_) => 2
        Load32S(_) | Load32U(_) => 4
        _ => 1
      }
      // Emit bounds check: trap if wasm_addr + offset + access_size > memory_size
      emit_bounds_check(ctx, block, wasm_addr, offset, access_size)
      // Compute effective address: memory_base (X21) + wasm_addr
      let effective_addr = ctx.vcode_func.new_vreg(Int)
      let add_inst = VCodeInst::new(Add)
      add_inst.add_def({ reg: Virtual(effective_addr) })
      add_inst.add_use(Physical({ index: 21, class: Int })) // X21 = memory_base
      add_inst.add_use(Virtual(wasm_addr))
      block.add_inst(add_inst)
      // Check alignment requirement based on opcode type
      // Load8: any offset ok (1-byte aligned)
      // Load16: offset must be 2-aligned for immediate encoding
      // Load32: offset must be 4-aligned for immediate encoding
      let alignment = access_size
      // If offset is not aligned or too large, add it to the address first
      if offset != 0 && (offset % alignment != 0 || offset > 4095 * alignment) {
        // Add offset to effective_addr using immediate add
        let addr_with_offset = ctx.vcode_func.new_vreg(Int)
        let offset_add = VCodeInst::new(AddImm(offset))
        offset_add.add_def({ reg: Virtual(addr_with_offset) })
        offset_add.add_use(Virtual(effective_addr))
        block.add_inst(offset_add)
        // Now load with offset=0
        let vcode_inst = VCodeInst::new(opcode_fn(0))
        vcode_inst.add_def({ reg: Virtual(dst) })
        vcode_inst.add_use(Virtual(addr_with_offset))
        block.add_inst(vcode_inst)
      } else {
        // Offset can be encoded directly in the load instruction
        let vcode_inst = VCodeInst::new(opcode_fn(offset))
        vcode_inst.add_def({ reg: Virtual(dst) })
        vcode_inst.add_use(Virtual(effective_addr))
        block.add_inst(vcode_inst)
      }
    }
    None => ()
  }
}

///|
/// Lower narrow store instruction (8/16/32-bit)
/// For WASM, addr is an offset within linear memory, so we need to add memory_base (X21)
fn lower_store_narrow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  offset : Int,
  mem_ty : MemType,
) -> Unit {
  // Store has no result, just uses: addr, value
  let wasm_addr = ctx.get_vreg_for_use(inst.operands[0], block)
  let value = ctx.get_vreg_for_use(inst.operands[1], block)
  // Determine access size for bounds check
  let access_size = mem_type_size(mem_ty)
  // Emit bounds check: trap if wasm_addr + offset + access_size > memory_size
  emit_bounds_check(ctx, block, wasm_addr, offset, access_size)
  // Compute effective address: memory_base (X21) + wasm_addr
  let effective_addr = ctx.vcode_func.new_vreg(Int)
  let add_inst = VCodeInst::new(Add)
  add_inst.add_def({ reg: Virtual(effective_addr) })
  add_inst.add_use(Physical({ index: 21, class: Int })) // X21 = memory_base
  add_inst.add_use(Virtual(wasm_addr))
  block.add_inst(add_inst)
  // Check alignment requirement based on memory type
  let alignment = access_size
  // If offset is not aligned or too large, add it to the address first
  if offset != 0 && (offset % alignment != 0 || offset > 4095 * alignment) {
    // Add offset to effective_addr using immediate add
    let addr_with_offset = ctx.vcode_func.new_vreg(Int)
    let offset_add = VCodeInst::new(AddImm(offset))
    offset_add.add_def({ reg: Virtual(addr_with_offset) })
    offset_add.add_use(Virtual(effective_addr))
    block.add_inst(offset_add)
    // Now store with offset=0
    let vcode_inst = VCodeInst::new(Store(mem_ty, 0))
    vcode_inst.add_use(Virtual(addr_with_offset))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  } else {
    // Offset can be encoded directly in the store instruction
    let vcode_inst = VCodeInst::new(Store(mem_ty, offset))
    vcode_inst.add_use(Virtual(effective_addr))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower extend operation (sign or zero extend)
fn lower_extend(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  signed~ : Bool,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg_for_use(inst.operands[0], block)
      // Determine the extend kind based on source and destination types
      let src_ty = inst.operands[0].ty
      let dst_ty = result.ty
      let kind = get_extend_kind(src_ty, dst_ty, signed)
      let vcode_inst = VCodeInst::new(Extend(kind))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Determine the extend kind based on source and destination types
fn get_extend_kind(
  src_ty : @ir.Type,
  dst_ty : @ir.Type,
  signed : Bool,
) -> ExtendKind {
  match (src_ty, dst_ty, signed) {
    (@ir.Type::I32, @ir.Type::I64, true) => Signed32To64
    (@ir.Type::I32, @ir.Type::I64, false) => Unsigned32To64
    // Default to 32->64 extend
    _ => if signed { Signed32To64 } else { Unsigned32To64 }
  }
}

///|
/// Lower truncate operation
fn lower_truncate(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg_for_use(inst.operands[0], block)
      let vcode_inst = VCodeInst::new(Truncate)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower float to int conversion
fn lower_float_to_int(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  signed~ : Bool,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg_for_use(inst.operands[0], block)
      // Determine conversion kind based on source/dest types and signedness
      let src_ty = inst.operands[0].ty
      let dst_ty = result.ty
      let kind : FloatToIntKind = match (src_ty, dst_ty, signed) {
        (@ir.Type::F32, @ir.Type::I32, true) => F32ToI32S
        (@ir.Type::F32, @ir.Type::I32, false) => F32ToI32U
        (@ir.Type::F32, @ir.Type::I64, true) => F32ToI64S
        (@ir.Type::F32, @ir.Type::I64, false) => F32ToI64U
        (@ir.Type::F64, @ir.Type::I32, true) => F64ToI32S
        (@ir.Type::F64, @ir.Type::I32, false) => F64ToI32U
        (@ir.Type::F64, @ir.Type::I64, true) => F64ToI64S
        (@ir.Type::F64, @ir.Type::I64, false) => F64ToI64U
        _ => F64ToI64S // Default fallback
      }
      let vcode_inst = VCodeInst::new(FloatToInt(kind))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower int to float conversion
fn lower_int_to_float(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  signed~ : Bool,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg_for_use(inst.operands[0], block)
      // Determine conversion kind based on source/dest types and signedness
      let src_ty = inst.operands[0].ty
      let dst_ty = result.ty
      let kind : IntToFloatKind = match (src_ty, dst_ty, signed) {
        (@ir.Type::I32, @ir.Type::F32, true) => I32SToF32
        (@ir.Type::I32, @ir.Type::F32, false) => I32UToF32
        (@ir.Type::I64, @ir.Type::F32, true) => I64SToF32
        (@ir.Type::I64, @ir.Type::F32, false) => I64UToF32
        (@ir.Type::I32, @ir.Type::F64, true) => I32SToF64
        (@ir.Type::I32, @ir.Type::F64, false) => I32UToF64
        (@ir.Type::I64, @ir.Type::F64, true) => I64SToF64
        (@ir.Type::I64, @ir.Type::F64, false) => I64UToF64
        _ => I64SToF64 // Default fallback
      }
      let vcode_inst = VCodeInst::new(IntToFloat(kind))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower copy instruction
fn lower_copy(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg_for_use(inst.operands[0], block)
      let vcode_inst = VCodeInst::new(Move)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower select instruction (cond ? true_val : false_val)
/// Uses AArch64 CSEL instruction: if cond != 0, select true_val, else false_val
fn lower_select(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let cond = ctx.get_vreg_for_use(inst.operands[0], block)
      let true_val = ctx.get_vreg_for_use(inst.operands[1], block)
      let false_val = ctx.get_vreg_for_use(inst.operands[2], block)

      // Emit Select instruction: dst = cond != 0 ? true_val : false_val
      let vcode_inst = VCodeInst::new(Select)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(cond))
      vcode_inst.add_use(Virtual(true_val))
      vcode_inst.add_use(Virtual(false_val))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower a terminator
fn lower_terminator(
  ctx : LoweringContext,
  term : @ir.Terminator,
  block : VCodeBlock,
) -> Unit {
  match term {
    @ir.Terminator::Jump(target, args) => {
      let target_id = ctx.get_block_id(target)
      // Generate moves for block arguments
      // Find the target block's parameters
      for tb in ctx.ir_func.blocks {
        if tb.id == target {
          for i, param_info in tb.params {
            if i < args.length() {
              // Get the source value's vreg
              let src = ctx.get_vreg_for_use(args[i], block)
              // Get the destination param's vreg
              let (param_value, _param_ty) = param_info
              let dst = ctx.get_vreg(param_value)
              // Emit a move instruction
              let mov_inst = VCodeInst::new(Move)
              mov_inst.add_def({ reg: Virtual(dst) })
              mov_inst.add_use(Virtual(src))
              block.add_inst(mov_inst)
            }
          }
          break
        }
      }
      block.set_terminator(Jump(target_id))
    }
    @ir.Terminator::Brz(cond, then_block, else_block) => {
      let cond_vreg = ctx.get_vreg_for_use(cond, block)
      let then_id = ctx.get_block_id(then_block)
      let else_id = ctx.get_block_id(else_block)
      // brz means branch if zero, so swap then/else for Branch semantics
      block.set_terminator(Branch(Virtual(cond_vreg), else_id, then_id))
    }
    @ir.Terminator::Brnz(cond, then_block, else_block) => {
      let cond_vreg = ctx.get_vreg_for_use(cond, block)
      let then_id = ctx.get_block_id(then_block)
      let else_id = ctx.get_block_id(else_block)
      block.set_terminator(Branch(Virtual(cond_vreg), then_id, else_id))
    }
    @ir.Terminator::Return(values) => {
      let regs : Array[Reg] = []
      for v in values {
        regs.push(Virtual(ctx.get_vreg_for_use(v, block)))
      }
      block.set_terminator(Return(regs))
    }
    @ir.Terminator::Trap(msg) => block.set_terminator(Trap(msg))
    @ir.Terminator::BrTable(index, targets, default) => {
      // Lower br_table using a comparison chain
      // For each target at position i, compare index with i and branch if equal
      let index_vreg = ctx.get_vreg_for_use(index, block)
      let default_id = ctx.get_block_id(default)
      if targets.is_empty() {
        // No targets, just jump to default
        block.set_terminator(Jump(default_id))
      } else {
        // Create comparison chain blocks
        // We need N-1 blocks where N = number of targets
        // Original block handles index 0
        // Chain block i-1 handles index i (for i = 1..N-1)
        // The last comparison branches to default if not equal
        let chain_blocks : Array[VCodeBlock] = []
        for _ in 0..<(targets.length() - 1) {
          chain_blocks.push(ctx.vcode_func.new_block())
        }

        // First comparison goes in the original block
        // Compare index with 0
        let cmp_result_0 = ctx.vcode_func.new_vreg(Int)
        let zero_vreg = ctx.vcode_func.new_vreg(Int)

        // Load constant 0
        let load_zero = VCodeInst::new(LoadConst(0L))
        load_zero.add_def({ reg: Virtual(zero_vreg) })
        block.add_inst(load_zero)

        // Compare index with 0: cmp_result = (index == 0)
        let cmp_inst_0 = VCodeInst::new(Cmp(Eq))
        cmp_inst_0.add_def({ reg: Virtual(cmp_result_0) })
        cmp_inst_0.add_use(Virtual(index_vreg))
        cmp_inst_0.add_use(Virtual(zero_vreg))
        block.add_inst(cmp_inst_0)

        // Branch: if equal go to targets[0], else go to chain_blocks[0] (next comparison)
        let target_0_id = ctx.get_block_id(targets[0])
        if targets.length() == 1 {
          // Only one target, else goes to default
          block.set_terminator(
            Branch(Virtual(cmp_result_0), target_0_id, default_id),
          )
        } else {
          block.set_terminator(
            Branch(Virtual(cmp_result_0), target_0_id, chain_blocks[0].id),
          )
        }

        // Fill in the chain blocks for indices 1 to N-1
        for i in 1..<targets.length() {
          let chain_block = chain_blocks[i - 1]
          let target_id = ctx.get_block_id(targets[i])

          // Load constant i
          let const_vreg = ctx.vcode_func.new_vreg(Int)
          let load_const = VCodeInst::new(LoadConst(i.to_int64()))
          load_const.add_def({ reg: Virtual(const_vreg) })
          chain_block.add_inst(load_const)

          // Compare index with i
          let cmp_result = ctx.vcode_func.new_vreg(Int)
          let cmp_inst = VCodeInst::new(Cmp(Eq))
          cmp_inst.add_def({ reg: Virtual(cmp_result) })
          cmp_inst.add_use(Virtual(index_vreg))
          cmp_inst.add_use(Virtual(const_vreg))
          chain_block.add_inst(cmp_inst)

          // Branch: if equal go to targets[i], else go to next chain block or default
          if i == targets.length() - 1 {
            // Last comparison, else goes to default
            chain_block.set_terminator(
              Branch(Virtual(cmp_result), target_id, default_id),
            )
          } else {
            chain_block.set_terminator(
              Branch(Virtual(cmp_result), target_id, chain_blocks[i].id),
            )
          }
        }
      }
    }
  }
}

///|
/// Lower a direct function call
/// Generates code to:
/// 1. Load the function pointer from the function table (base at X20)
/// 2. Call through the function pointer with arguments
fn lower_call(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  func_idx : Int,
) -> Unit {
  // Collect argument vregs
  let arg_vregs : Array[VReg] = []
  for operand in inst.operands {
    arg_vregs.push(ctx.get_vreg_for_use(operand, block))
  }
  let num_args = arg_vregs.length()

  // Get all results (primary result + extra_results)
  let all_results = inst.all_results()
  let num_results = all_results.length()

  // Create a temporary vreg for the function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)

  // Step 1: Load function pointer from table
  // Function table base is assumed to be in X20 (a callee-saved register)
  // func_ptr = [X20 + func_idx * 8]
  let offset = func_idx * 8
  let load_inst = VCodeInst::new(Load(I64, offset))
  load_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  // We use physical register X20 as the function table base
  load_inst.add_use(Physical({ index: 20, class: Int }))
  block.add_inst(load_inst)

  // Step 2: Emit CallIndirect instruction
  let call_inst = VCodeInst::new(CallIndirect(num_args, num_results))
  // Define all results
  for result in all_results {
    let dst = ctx.get_vreg(result)
    call_inst.add_def({ reg: Virtual(dst) })
  }
  // Add clobbers for all caller-saved registers
  // This tells the register allocator that these registers are destroyed by the call
  add_call_clobbers(call_inst)
  // Uses: function pointer first, then arguments
  call_inst.add_use(Virtual(func_ptr_vreg))
  for arg_vreg in arg_vregs {
    call_inst.add_use(Virtual(arg_vreg))
  }
  block.add_inst(call_inst)
}

///|
/// Lower memory.grow instruction
/// memory.grow takes a delta (number of pages to grow) and returns the previous size or -1
fn lower_memory_grow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  // Get the delta operand
  let delta_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Create the MemoryGrow VCode instruction
  // Uses: [delta], Defs: [result]
  let grow_inst = VCodeInst::new(MemoryGrow)
  grow_inst.add_def({ reg: Virtual(result_vreg) })
  grow_inst.add_use(Virtual(delta_vreg))
  // Add clobbers for caller-saved registers (it's a call)
  add_call_clobbers(grow_inst)
  block.add_inst(grow_inst)
}

///|
/// Lower memory.size instruction
/// memory.size returns the current memory size in pages
fn lower_memory_size(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Create the MemorySize VCode instruction
  // Uses: [], Defs: [result]
  let size_inst = VCodeInst::new(MemorySize)
  size_inst.add_def({ reg: Virtual(result_vreg) })
  // Add clobbers for caller-saved registers (it's a call)
  add_call_clobbers(size_inst)
  block.add_inst(size_inst)
}

///|
/// Lower an indirect function call (call_indirect)
/// The callee is already on the stack as a function table index
fn lower_call_indirect(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  // For call_indirect, the first operand is the table index (callee)
  // which we need to convert to a function pointer
  if inst.operands.length() == 0 {
    return
  }

  // First operand is the table index (callee)
  let table_idx_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Arguments are all operands except the first one
  let arg_vregs : Array[VReg] = []
  for i in 1..<inst.operands.length() {
    arg_vregs.push(ctx.get_vreg_for_use(inst.operands[i], block))
  }
  let num_args = arg_vregs.length()

  // Get all results (primary result + extra_results)
  let all_results = inst.all_results()
  let num_results = all_results.length()

  // Create temporaries for calculation
  let offset_vreg = ctx.vcode_func.new_vreg(Int)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)

  // Step 1: Calculate offset = table_idx * 8
  let const_8_vreg = ctx.vcode_func.new_vreg(Int)
  let load_8 = VCodeInst::new(LoadConst(8L))
  load_8.add_def({ reg: Virtual(const_8_vreg) })
  block.add_inst(load_8)
  let mul_inst = VCodeInst::new(Mul)
  mul_inst.add_def({ reg: Virtual(offset_vreg) })
  mul_inst.add_use(Virtual(table_idx_vreg))
  mul_inst.add_use(Virtual(const_8_vreg))
  block.add_inst(mul_inst)

  // Step 2: Calculate address = X24 + offset
  // X24 holds the indirect_table_ptr (separate from func_table in X20)
  let addr_vreg = ctx.vcode_func.new_vreg(Int)
  let add_inst = VCodeInst::new(Add)
  add_inst.add_def({ reg: Virtual(addr_vreg) })
  add_inst.add_use(Physical({ index: 24, class: Int }))
  add_inst.add_use(Virtual(offset_vreg))
  block.add_inst(add_inst)

  // Step 3: Load function pointer from address
  let load_inst = VCodeInst::new(Load(I64, 0))
  load_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  load_inst.add_use(Virtual(addr_vreg))
  block.add_inst(load_inst)

  // Step 4: Emit CallIndirect instruction
  let call_inst = VCodeInst::new(CallIndirect(num_args, num_results))
  // Define all results
  for result in all_results {
    let dst = ctx.get_vreg(result)
    call_inst.add_def({ reg: Virtual(dst) })
  }
  // Add clobbers for all caller-saved registers
  // This tells the register allocator that these registers are destroyed by the call
  add_call_clobbers(call_inst)
  // Uses: function pointer first, then arguments
  call_inst.add_use(Virtual(func_ptr_vreg))
  for arg_vreg in arg_vregs {
    call_inst.add_use(Virtual(arg_vreg))
  }
  block.add_inst(call_inst)
}

///|
/// Add clobber definitions for all caller-saved registers to a call instruction.
/// This tells the register allocator that these registers are destroyed by the call,
/// so any values that need to survive across the call must be spilled or allocated
/// to callee-saved registers.
fn add_call_clobbers(call_inst : VCodeInst) -> Unit {
  // Add clobbers for all caller-saved GPRs (X0-X17)
  for preg in call_clobbered_gprs() {
    call_inst.add_def({ reg: Physical(preg) })
  }
  // Add clobbers for all caller-saved FPRs (D0-D7)
  for preg in call_clobbered_fprs() {
    call_inst.add_def({ reg: Physical(preg) })
  }
}
