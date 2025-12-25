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
  // Map from IR Value id to @abi.VReg
  value_map : Map[Int, @abi.VReg]
  // Map from IR Block id to VCode block id
  block_map : Map[Int, Int]
  // Map from IR Value id to stack param index (for params >= 8)
  stack_param_map : Map[Int, (Int, @abi.RegClass)]
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
/// Get or create a @abi.VReg for an IR Value
fn LoweringContext::get_vreg(
  self : LoweringContext,
  value : @ir.Value,
) -> @abi.VReg {
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
/// Get @abi.VReg for an IR Value, generating LoadStackParam if it's a stack parameter
/// This should be used when lowering instructions that use values
fn LoweringContext::get_vreg_for_use(
  self : LoweringContext,
  value : @ir.Value,
  block : @block.VCodeBlock,
) -> @abi.VReg {
  // First check if it's a stack parameter
  if self.stack_param_map.get(value.id) is Some((param_idx, class)) {
    // Generate LoadStackParam instruction
    // Pass int_stack_params so emit can calculate correct offset for float overflow params
    let result = self.vcode_func.new_vreg(class)
    let inst = @instr.VCodeInst::new(
      LoadStackParam(param_idx, class, self.vcode_func.int_stack_params),
    )
    inst.add_def({ reg: Virtual(result) })
    block.add_inst(inst)
    result
  } else {
    // Not a stack param, use normal get_vreg
    self.get_vreg(value)
  }
}

///|
/// Create a new @abi.VReg with the given class
#warnings("-unused_value")
fn LoweringContext::new_vreg(
  self : LoweringContext,
  class : @abi.RegClass,
) -> @abi.VReg {
  self.vcode_func.new_vreg(class)
}

///|
/// Get VCode block id for an IR block id
fn LoweringContext::get_block_id(
  self : LoweringContext,
  ir_block_id : Int,
) -> Int {
  self.block_map.get(ir_block_id).unwrap()
}

///|
/// Convert IR Type to @abi.RegClass
fn ir_type_to_reg_class(ty : @ir.Type) -> @abi.RegClass {
  match ty {
    @ir.Type::I32 | @ir.Type::I64 | @ir.Type::FuncRef | @ir.Type::ExternRef =>
      Int
    @ir.Type::F32 => Float32
    @ir.Type::F64 => Float64
  }
}

///|
/// Convert IR Type to @instr.MemType
fn ir_type_to_mem_type(ty : @ir.Type) -> @instr.MemType {
  match ty {
    @ir.Type::I32 => I32
    @ir.Type::I64 => I64
    @ir.Type::F32 => F32
    @ir.Type::F64 => F64
    // Reference types use 64-bit storage (-1L as null sentinel)
    @ir.Type::FuncRef | @ir.Type::ExternRef => I64
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
  if find_defining_inst(ctx, value) is Some(inst) &&
    inst.opcode is @ir.Opcode::Ishl {
    // Check if shift amount is a constant
    let shift_operand = inst.operands[1]
    if find_defining_inst(ctx, shift_operand) is Some(shift_inst) &&
      shift_inst.opcode is @ir.Opcode::Iconst(amount) {
      let shift_val = amount.to_int()
      if shift_val >= 0 && shift_val <= 63 {
        return Some((inst.operands[0], shift_val))
      }
    }
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
  if find_defining_inst(ctx, value) is Some(inst) &&
    inst.opcode is @ir.Opcode::Imul {
    return Some((inst.operands[0], inst.operands[1]))
  }
  None
}

///|
/// Check if a value is the constant 0
fn is_const_zero_value(ctx : LoweringContext, value : @ir.Value) -> Bool {
  if find_defining_inst(ctx, value) is Some(inst) &&
    inst.opcode is @ir.Opcode::Iconst(val) {
    return val == 0L
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
  // v3 ABI with separate int/float register pools:
  // - params[0] = callee_vmctx (X0) - always int register
  // - params[1] = caller_vmctx (X1) - always int register
  // - user int params: X2-X7 (up to 6)
  // - user float params: V0-V7 (up to 8)
  // - overflow: int overflow first, then float overflow
  let max_int_reg_params = @abi.MAX_REG_PARAMS // X0-X7 (includes vmctx which ARE in ir_func.params)
  let max_float_reg_params = @abi.MAX_FLOAT_REG_PARAMS // V0-V7
  let mut int_reg_count = 0
  let mut float_reg_count = 0
  let mut int_stack_count = 0
  let mut float_stack_count = 0
  for param in ir_func.params {
    let (value, ty) = param
    let class = ir_type_to_reg_class(ty)
    match class {
      Int =>
        if int_reg_count < max_int_reg_params {
          // Register parameter: allocate @abi.VReg
          let vreg = ctx.vcode_func.add_param(class)
          ctx.value_map.set(value.id, vreg)
          int_reg_count = int_reg_count + 1
        } else {
          // Stack parameter: int overflow comes first in stack layout
          ctx.stack_param_map.set(value.id, (int_stack_count, class))
          int_stack_count = int_stack_count + 1
        }
      Float32 | Float64 =>
        if float_reg_count < max_float_reg_params {
          // Register parameter: allocate @abi.VReg
          let vreg = ctx.vcode_func.add_param(class)
          ctx.value_map.set(value.id, vreg)
          float_reg_count = float_reg_count + 1
        } else {
          // Stack parameter: float overflow comes after int overflow
          // We encode this as negative index to distinguish from int
          // Actual offset = int_overflow_count * 8 + float_idx * 8
          // We'll compute this in emit using special encoding
          ctx.stack_param_map.set(value.id, (-(float_stack_count + 1), class)) // negative = float stack param
          float_stack_count = float_stack_count + 1
        }
    }
  }
  // Store int overflow count for emit to calculate correct offsets
  ctx.vcode_func.set_int_stack_params(int_stack_count)

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
  vcode_block : @block.VCodeBlock,
) -> Unit {
  // Block parameters are already handled in pre-registration phase

  // Lower instructions
  for inst in ir_block.instructions {
    lower_inst(ctx, inst, vcode_block)
  }

  // Lower terminator
  if ir_block.terminator is Some(term) {
    lower_terminator(ctx, term, vcode_block)
  }
}

///|
/// Lower a single IR instruction to VCode
fn lower_inst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  match inst.opcode {
    // Constants
    @ir.Opcode::Iconst(val) => lower_iconst(ctx, inst, block, val)
    @ir.Opcode::Fconst(val) => lower_fconst(ctx, inst, block, val)

    // Integer arithmetic - with pattern matching for AArch64
    @ir.Opcode::Iadd => lower_iadd(ctx, inst, block)
    @ir.Opcode::Isub => lower_isub(ctx, inst, block)
    @ir.Opcode::Imul => lower_imul(ctx, inst, block)
    @ir.Opcode::Sdiv => lower_div(ctx, inst, block, signed=true)
    @ir.Opcode::Udiv => lower_div(ctx, inst, block, signed=false)
    @ir.Opcode::Srem => lower_rem(ctx, inst, block, true)
    @ir.Opcode::Urem => lower_rem(ctx, inst, block, false)

    // Bitwise operations - with pattern matching for shifted operands
    @ir.Opcode::Band => lower_band(ctx, inst, block)
    @ir.Opcode::Bor => lower_bor(ctx, inst, block)
    @ir.Opcode::Bxor => lower_bxor(ctx, inst, block)
    @ir.Opcode::Ishl => lower_shift(ctx, inst, block, fn(is_64) { Shl(is_64) })
    @ir.Opcode::Sshr => lower_shift(ctx, inst, block, fn(is_64) { AShr(is_64) })
    @ir.Opcode::Ushr => lower_shift(ctx, inst, block, fn(is_64) { LShr(is_64) })
    @ir.Opcode::Rotl => lower_rotl(ctx, inst, block)
    @ir.Opcode::Rotr => lower_shift(ctx, inst, block, fn(is_64) { Rotr(is_64) })
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
    @ir.Opcode::Clz =>
      lower_bitcount(ctx, inst, block, fn(is_64) { Clz(is_64) })
    @ir.Opcode::Ctz => lower_ctz(ctx, inst, block)
    @ir.Opcode::Popcnt =>
      lower_bitcount(ctx, inst, block, fn(is_64) { Popcnt(is_64) })

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
    @ir.Opcode::Sextend8 => lower_sextend_inplace(ctx, inst, block, from_bits=8)
    @ir.Opcode::Sextend16 =>
      lower_sextend_inplace(ctx, inst, block, from_bits=16)
    @ir.Opcode::Sextend32 =>
      lower_sextend_inplace(ctx, inst, block, from_bits=32)
    @ir.Opcode::Ireduce => lower_truncate(ctx, inst, block)
    @ir.Opcode::FcvtToSint => lower_float_to_int(ctx, inst, block, signed=true)
    @ir.Opcode::FcvtToUint => lower_float_to_int(ctx, inst, block, signed=false)
    @ir.Opcode::FcvtToSintSat =>
      lower_float_to_int_sat(ctx, inst, block, signed=true)
    @ir.Opcode::FcvtToUintSat =>
      lower_float_to_int_sat(ctx, inst, block, signed=false)
    @ir.Opcode::SintToFcvt => lower_int_to_float(ctx, inst, block, signed=true)
    @ir.Opcode::UintToFcvt => lower_int_to_float(ctx, inst, block, signed=false)
    @ir.Opcode::Fpromote => lower_promote(ctx, inst, block)
    @ir.Opcode::Fdemote => lower_demote(ctx, inst, block)
    @ir.Opcode::Bitcast => lower_bitcast(ctx, inst, block)

    // Misc
    @ir.Opcode::Copy => lower_copy(ctx, inst, block)
    @ir.Opcode::Select => lower_select(ctx, inst, block)

    // Memory management
    @ir.Opcode::MemoryGrow(max_pages) =>
      lower_memory_grow(ctx, inst, block, max_pages)
    @ir.Opcode::MemorySize => lower_memory_size(ctx, inst, block)
    @ir.Opcode::MemoryFill => lower_memory_fill(ctx, inst, block)
    @ir.Opcode::MemoryCopy => lower_memory_copy(ctx, inst, block)

    // Table operations
    @ir.Opcode::TableGet(table_idx) =>
      lower_table_get(ctx, inst, block, table_idx)
    @ir.Opcode::TableSet(table_idx) =>
      lower_table_set(ctx, inst, block, table_idx)
    @ir.Opcode::TableSize(table_idx) =>
      lower_table_size(ctx, inst, block, table_idx)
    @ir.Opcode::TableGrow(table_idx) =>
      lower_table_grow(ctx, inst, block, table_idx)

    // Global operations
    @ir.Opcode::GlobalGet(global_idx) =>
      lower_global_get(ctx, inst, block, global_idx)
    @ir.Opcode::GlobalSet(global_idx) =>
      lower_global_set(ctx, inst, block, global_idx)

    // Function calls
    @ir.Opcode::Call(func_idx) => lower_call(ctx, inst, block, func_idx)
    @ir.Opcode::CallIndirect(type_idx, table_idx) =>
      lower_call_indirect(ctx, inst, block, type_idx, table_idx)
    @ir.Opcode::CallRef(type_idx) => lower_call_ref(ctx, inst, block, type_idx)
    // Tail calls - use dedicated lowering functions with Cranelift-style parameter handling
    @ir.Opcode::ReturnCall(func_idx) =>
      lower_return_call(ctx, inst, block, func_idx)
    @ir.Opcode::ReturnCallIndirect(type_idx, table_idx) =>
      lower_return_call_indirect(ctx, inst, block, type_idx, table_idx)
    @ir.Opcode::ReturnCallRef(type_idx) =>
      lower_return_call_ref(ctx, inst, block, type_idx)

    // Function reference
    @ir.Opcode::GetFuncRef(func_idx) =>
      lower_get_func_ref(ctx, inst, block, func_idx)

    // Raw pointer operations (for trampolines)
    @ir.Opcode::LoadPtr(ty) => lower_load_ptr(ctx, inst, block, ty)
    @ir.Opcode::StorePtr(ty) => lower_store_ptr(ctx, inst, block, ty)
    @ir.Opcode::CallPtr(num_args, num_results) =>
      lower_call_ptr(ctx, inst, block, num_args, num_results)

    // GC operations - i31 (simple bit manipulation, implemented inline)
    @ir.Opcode::I31New => lower_i31_new(ctx, inst, block)
    @ir.Opcode::I31GetS => lower_i31_get_s(ctx, inst, block)
    @ir.Opcode::I31GetU => lower_i31_get_u(ctx, inst, block)

    // GC operations - type conversions (no-ops for JIT, just pass through)
    @ir.Opcode::AnyConvertExtern | @ir.Opcode::ExternConvertAny =>
      lower_gc_convert(ctx, inst, block)

    // GC operations - struct/array (use runtime libcalls)
    @ir.Opcode::StructNew(type_idx) =>
      lower_struct_new(ctx, inst, block, type_idx)
    @ir.Opcode::StructNewDefault(type_idx) =>
      lower_struct_new_default(ctx, inst, block, type_idx)
    @ir.Opcode::StructGet(type_idx, field_idx) =>
      lower_struct_get(ctx, inst, block, type_idx, field_idx)
    @ir.Opcode::StructGetS(type_idx, field_idx, byte_width) =>
      lower_struct_get_s(ctx, inst, block, type_idx, field_idx, byte_width)
    @ir.Opcode::StructGetU(type_idx, field_idx, byte_width) =>
      lower_struct_get_u(ctx, inst, block, type_idx, field_idx, byte_width)
    @ir.Opcode::StructSet(type_idx, field_idx) =>
      lower_struct_set(ctx, inst, block, type_idx, field_idx)
    @ir.Opcode::ArrayNew(type_idx) =>
      lower_array_new(ctx, inst, block, type_idx)
    @ir.Opcode::ArrayNewDefault(type_idx) =>
      lower_array_new_default(ctx, inst, block, type_idx)
    @ir.Opcode::ArrayNewFixed(type_idx, len) =>
      lower_array_new_fixed(ctx, inst, block, type_idx, len)
    @ir.Opcode::ArrayGet(type_idx) =>
      lower_array_get(ctx, inst, block, type_idx)
    @ir.Opcode::ArrayGetS(type_idx, byte_width) =>
      lower_array_get_s(ctx, inst, block, type_idx, byte_width)
    @ir.Opcode::ArrayGetU(type_idx, byte_width) =>
      lower_array_get_u(ctx, inst, block, type_idx, byte_width)
    @ir.Opcode::ArraySet(type_idx) =>
      lower_array_set(ctx, inst, block, type_idx)
    @ir.Opcode::ArrayLen => lower_array_len(ctx, inst, block)
    @ir.Opcode::ArrayFill(type_idx) =>
      lower_array_fill(ctx, inst, block, type_idx)
    @ir.Opcode::ArrayCopy(dst_type, src_type) =>
      lower_array_copy(ctx, inst, block, dst_type, src_type)
    @ir.Opcode::RefTest(type_idx, nullable) =>
      lower_ref_test(ctx, inst, block, type_idx, nullable)
    @ir.Opcode::RefCast(type_idx, nullable) =>
      lower_ref_cast(ctx, inst, block, type_idx, nullable)
    @ir.Opcode::RefEq => lower_ref_eq(ctx, inst, block)
  }
}

///|
/// Lower integer constant
fn lower_iconst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  val : Int64,
) -> Unit {
  if inst.result is Some(result) {
    let vreg = ctx.get_vreg(result)
    let vcode_inst = @instr.VCodeInst::new(LoadConst(val))
    vcode_inst.add_def({ reg: Virtual(vreg) })
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower float constant
fn lower_fconst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  val : Double,
) -> Unit {
  if inst.result is Some(result) {
    let vreg = ctx.get_vreg(result)
    // Determine if this is an F32 or F64 constant based on the result type
    let opcode = match result.ty {
      @ir.Type::F32 => {
        // F32 bits are packed in the lower 32 bits of the Double's bit representation
        // (see IRBuilder::fconst_f32). Extract them directly to preserve NaN payloads.
        let bits = val.reinterpret_as_int64().to_int()
        @instr.LoadConstF32(bits)
      }
      _ => {
        // F64: get 64-bit representation
        let bits = val.reinterpret_as_int64()
        LoadConstF64(bits)
      }
    }
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(vreg) })
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower binary integer operation
fn lower_binary_int(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  opcode : @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    vcode_inst.add_use(Virtual(rhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower division with proper 32/64-bit selection and trapping
fn lower_div(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  signed~ : Bool,
) -> Unit {
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
  let is_64 = inst.operands[0].ty is @ir.Type::I64

  // Trap if divisor is zero (trap_code 4 = integer divide by zero)
  // Must always emit even if result is unused (for side effect)
  let trap_zero = @instr.VCodeInst::new(TrapIfZero(is_64, 4))
  trap_zero.add_use(Virtual(rhs))
  block.add_inst(trap_zero)

  // For signed division, also trap if INT_MIN / -1 (would overflow)
  // Use trap_code 5 = integer overflow
  if signed {
    let trap_overflow = @instr.VCodeInst::new(TrapIfDivOverflow(is_64, 5))
    trap_overflow.add_use(Virtual(lhs))
    trap_overflow.add_use(Virtual(rhs))
    block.add_inst(trap_overflow)
  }

  // Only emit division if result is used
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let opcode : @instr.VCodeOpcode = if signed {
      @instr.VCodeOpcode::SDiv(is_64)
    } else {
      @instr.VCodeOpcode::UDiv(is_64)
    }
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    vcode_inst.add_use(Virtual(rhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower shift/rotate operations with proper 32/64-bit selection
fn lower_shift(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  make_opcode : (Bool) -> @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let is_64 = result.ty is @ir.Type::I64
    let vcode_inst = @instr.VCodeInst::new(make_opcode(is_64))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    vcode_inst.add_use(Virtual(rhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower bit counting operations (clz, popcnt) with proper 32/64-bit selection
fn lower_bitcount(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  make_opcode : (Bool) -> @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let is_64 = result.ty is @ir.Type::I64
    let vcode_inst = @instr.VCodeInst::new(make_opcode(is_64))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
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
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: add(x, mul(y, z)) -> MADD
  if match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
    let acc = ctx.get_vreg_for_use(lhs_val, block)
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let vcode_inst = @instr.VCodeInst::new(Madd)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(acc)) // accumulator
    vcode_inst.add_use(Virtual(src1)) // multiplicand
    vcode_inst.add_use(Virtual(src2)) // multiplier
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: add(mul(x, y), z) -> MADD (commutative)
  if match_mul_value(ctx, lhs_val) is Some((mul_lhs, mul_rhs)) {
    let acc = ctx.get_vreg_for_use(rhs_val, block)
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let vcode_inst = @instr.VCodeInst::new(Madd)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(acc))
    vcode_inst.add_use(Virtual(src1))
    vcode_inst.add_use(Virtual(src2))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: add(x, shl(y, n)) -> AddShifted
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AddShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: add(shl(x, n), y) -> AddShifted (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AddShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Default: regular add
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let is_64 = result.ty is @ir.Type::I64
  let vcode_inst = @instr.VCodeInst::new(Add(is_64))
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower integer multiply with proper 32/64-bit size
fn lower_imul(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
  let is_64 = result.ty is @ir.Type::I64
  let vcode_inst = @instr.VCodeInst::new(Mul(is_64))
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
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: sub(0, mul(x, y)) -> MNEG
  if is_const_zero_value(ctx, lhs_val) &&
    match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let vcode_inst = @instr.VCodeInst::new(Mneg)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src1))
    vcode_inst.add_use(Virtual(src2))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: sub(x, mul(y, z)) -> MSUB
  if match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
    let acc = ctx.get_vreg_for_use(lhs_val, block)
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let vcode_inst = @instr.VCodeInst::new(Msub)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(acc))
    vcode_inst.add_use(Virtual(src1))
    vcode_inst.add_use(Virtual(src2))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: sub(x, shl(y, n)) -> SubShifted
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(SubShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Default: regular sub
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let is_64 = result.ty is @ir.Type::I64
  let vcode_inst = @instr.VCodeInst::new(Sub(is_64))
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
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: and(x, shl(y, n)) -> AndShifted
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AndShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: and(shl(x, n), y) -> AndShifted (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AndShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Default: regular and
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = @instr.VCodeInst::new(And)
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
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: or(x, shl(y, n)) -> OrShifted
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(OrShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: or(shl(x, n), y) -> OrShifted (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(OrShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Default: regular or
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = @instr.VCodeInst::new(Or)
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
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: xor(x, shl(y, n)) -> XorShifted
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(XorShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: xor(shl(x, n), y) -> XorShifted (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(XorShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Default: regular xor
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = @instr.VCodeInst::new(Xor)
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower rotate left instruction
/// Cranelift-style lowering: expand to primitive instructions here
/// rotl(x, n) = rotr(x, 0 - n)
///
/// AArch64 ROR only looks at lower bits of shift amount, so negating
/// via two's complement effectively gives us (size - n) mod size.
///
/// Generated sequence:
/// 1. zero = LoadConst(0)
/// 2. neg_n = Sub(zero, n)
/// 3. result = Rotr(x, neg_n)
fn lower_rotl(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  let amount = ctx.get_vreg_for_use(inst.operands[1], block)
  let is_64 = result.ty is @ir.Type::I64

  // Step 1: Load constant 0 into temp
  let zero = ctx.vcode_func.new_vreg(Int)
  let load_zero = @instr.VCodeInst::new(LoadConst(0L))
  load_zero.add_def({ reg: Virtual(zero) })
  block.add_inst(load_zero)

  // Step 2: Compute (0 - n) = -n
  let neg_n = ctx.vcode_func.new_vreg(Int)
  let sub_inst = @instr.VCodeInst::new(Sub(is_64))
  sub_inst.add_def({ reg: Virtual(neg_n) })
  sub_inst.add_use(Virtual(zero))
  sub_inst.add_use(Virtual(amount))
  block.add_inst(sub_inst)

  // Step 3: Rotate right by -n (effectively rotl by n)
  let rotr_inst = @instr.VCodeInst::new(Rotr(is_64))
  rotr_inst.add_def({ reg: Virtual(dst) })
  rotr_inst.add_use(Virtual(src))
  rotr_inst.add_use(Virtual(neg_n))
  block.add_inst(rotr_inst)
}

///|
/// Lower count trailing zeros instruction
/// Cranelift-style lowering: expand to primitive instructions here
/// ctz(x) = clz(rbit(x))
///
/// Generated sequence:
/// 1. temp = Rbit(x)
/// 2. result = Clz(temp)
fn lower_ctz(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  let is_64 = result.ty is @ir.Type::I64

  // Step 1: Reverse bits
  let reversed = ctx.vcode_func.new_vreg(Int)
  let rbit_inst = @instr.VCodeInst::new(Rbit(is_64))
  rbit_inst.add_def({ reg: Virtual(reversed) })
  rbit_inst.add_use(Virtual(src))
  block.add_inst(rbit_inst)

  // Step 2: Count leading zeros
  let clz_inst = @instr.VCodeInst::new(Clz(is_64))
  clz_inst.add_def({ reg: Virtual(dst) })
  clz_inst.add_use(Virtual(reversed))
  block.add_inst(clz_inst)
}

///|
/// Lower binary float operation
fn lower_binary_float(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // Determine if this is f32 based on result type
    let is_f32 = result.ty is @ir.Type::F32
    // Select VCode opcode based on IR opcode
    let opcode : @instr.VCodeOpcode = match inst.opcode {
      @ir.Opcode::Fadd => FAdd(is_f32)
      @ir.Opcode::Fsub => FSub(is_f32)
      @ir.Opcode::Fmul => FMul(is_f32)
      @ir.Opcode::Fdiv => FDiv(is_f32)
      @ir.Opcode::Fmin => FMin(is_f32)
      @ir.Opcode::Fmax => FMax(is_f32)
      _ => FAdd(is_f32) // Fallback, should not happen
    }
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    vcode_inst.add_use(Virtual(rhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower floating-point unary operation (sqrt, abs, neg, ceil, floor, trunc, nearest, promote, demote)
fn lower_unary_float(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    // Determine if this is f32 based on result type
    let is_f32 = result.ty is @ir.Type::F32
    // Select VCode opcode based on IR opcode
    let opcode : @instr.VCodeOpcode = match inst.opcode {
      @ir.Opcode::Fsqrt => FSqrt(is_f32)
      @ir.Opcode::Fabs => FAbs(is_f32)
      @ir.Opcode::Fneg => FNeg(is_f32)
      @ir.Opcode::Fceil => FCeil(is_f32)
      @ir.Opcode::Ffloor => FFloor(is_f32)
      @ir.Opcode::Ftrunc => FTrunc(is_f32)
      @ir.Opcode::Fnearest => FNearest(is_f32)
      _ => FSqrt(is_f32) // Fallback, should not happen
    }
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower f32 to f64 promotion
fn lower_promote(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(FPromote)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower f64 to f32 demotion
fn lower_demote(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(FDemote)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower integer unary operation (not)
fn lower_unary_int(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  opcode : @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower integer remainder: rem = a - (a / b) * b
/// Cranelift-style lowering: expand to primitive instructions here
///
/// AArch64 doesn't have a direct remainder instruction, so we expand:
///   div = a / b  (SDIV or UDIV)
///   result = msub(div, b, a) = a - div * b
///
/// Generated sequence:
/// 1. div = SDiv/UDiv(a, b)
/// 2. result = Msub(div, b, a)
fn lower_rem(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  signed : Bool,
) -> Unit {
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block) // a (dividend)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block) // b (divisor)
  let is_64 = inst.operands[0].ty is @ir.Type::I64

  // Trap if divisor is zero (trap_code 4 = integer divide by zero)
  // Must always emit even if result is unused (for side effect)
  let trap_zero = @instr.VCodeInst::new(TrapIfZero(is_64, 4))
  trap_zero.add_use(Virtual(rhs))
  block.add_inst(trap_zero)

  // Only emit remainder computation if result is used
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)

    // Step 1: Compute quotient = a / b
    let quotient = ctx.vcode_func.new_vreg(Int)
    let div_opcode = if signed {
      @instr.SDiv(is_64)
    } else {
      @instr.UDiv(is_64)
    }
    let div_inst = @instr.VCodeInst::new(div_opcode)
    div_inst.add_def({ reg: Virtual(quotient) })
    div_inst.add_use(Virtual(lhs))
    div_inst.add_use(Virtual(rhs))
    block.add_inst(div_inst)

    // Step 2: Compute remainder = a - quotient * b using MSUB
    // MSUB rd, rn, rm, ra computes: ra - rn * rm
    // We want: a - quotient * b, so: ra=a, rn=quotient, rm=b
    let msub_inst = @instr.VCodeInst::new(Msub)
    msub_inst.add_def({ reg: Virtual(dst) })
    msub_inst.add_use(Virtual(lhs)) // accumulator (a)
    msub_inst.add_use(Virtual(quotient)) // multiplicand
    msub_inst.add_use(Virtual(rhs)) // multiplier (b)
    block.add_inst(msub_inst)
  }
}

///|
/// Lower bitcast (reinterpret bits between int and float)
fn lower_bitcast(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(Bitcast)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Convert IR IntCC to VCode CmpKind
fn ir_intcc_to_cmp_kind(cc : @ir.IntCC) -> @instr.CmpKind {
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
  block : @block.VCodeBlock,
  cc : @ir.IntCC,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let kind = ir_intcc_to_cmp_kind(cc)
    // Determine is_64 from operand type, not result type (result is always i32)
    // Reference types (FuncRef, ExternRef) are also 64-bit values
    let is_64 = match inst.operands[0].ty {
      @ir.Type::I64 | @ir.Type::FuncRef | @ir.Type::ExternRef => true
      _ => false
    }
    let vcode_inst = @instr.VCodeInst::new(Cmp(kind, is_64))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    vcode_inst.add_use(Virtual(rhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Convert IR FloatCC to VCode FCmpKind
fn ir_floatcc_to_fcmp_kind(cc : @ir.FloatCC) -> @instr.FCmpKind {
  match cc {
    @ir.FloatCC::Eq => Eq
    @ir.FloatCC::Ne => Ne
    @ir.FloatCC::Lt => Lt
    @ir.FloatCC::Le => Le
    @ir.FloatCC::Gt => Gt
    @ir.FloatCC::Ge => Ge
  }
}

///|
/// Lower float comparison
fn lower_fcmp(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  cc : @ir.FloatCC,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let kind = ir_floatcc_to_fcmp_kind(cc)
    let vcode_inst = @instr.VCodeInst::new(FCmp(kind))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    vcode_inst.add_use(Virtual(rhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Get access size for a @instr.MemType
fn mem_type_size(ty : @instr.MemType) -> Int {
  match ty {
    I8 => 1
    I16 => 2
    I32 | F32 => 4
    I64 | F64 => 8
  }
}

///|
/// Emit bounds check instruction
/// Cranelift-style lowering: expand to primitive instructions here
///
/// Checks that wasm_addr + offset + access_size <= memory_size
///
/// Generated sequence:
/// 1. zero_ext = Extend(wasm_addr, Unsigned32To64) // zero-extend 32->64
/// 2. end_addr = Add(zero_ext, offset + access_size) // or AddImm
/// 3. memory_size = LoadPtr(vmctx, VMCTX_MEMORY_SIZE_OFFSET)
/// 4. TrapIfUgt(end_addr, memory_size, 1)
fn emit_bounds_check(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  wasm_addr : @abi.VReg,
  offset : Int,
  access_size : Int,
) -> Unit {
  // Step 1: Zero-extend wasm_addr from 32-bit to 64-bit
  let zero_ext = ctx.vcode_func.new_vreg(Int)
  let extend_inst = @instr.VCodeInst::new(Extend(Unsigned32To64))
  extend_inst.add_def({ reg: Virtual(zero_ext) })
  extend_inst.add_use(Virtual(wasm_addr))
  block.add_inst(extend_inst)

  // Step 2: Compute end_addr = zero_ext + (offset + access_size)
  // Handle offset as unsigned 32-bit, then add access_size
  let offset_u64 = offset
    .reinterpret_as_uint()
    .to_uint64()
    .reinterpret_as_int64()
  let end_offset = offset_u64 + access_size.to_int64()
  let end_addr = if end_offset > 0L {
    let result = ctx.vcode_func.new_vreg(Int)
    if end_offset <= 4095L {
      // Use AddImm for small offsets (64-bit pointer arithmetic)
      let add_inst = @instr.VCodeInst::new(AddImm(end_offset.to_int(), true))
      add_inst.add_def({ reg: Virtual(result) })
      add_inst.add_use(Virtual(zero_ext))
      block.add_inst(add_inst)
    } else {
      // Load constant and use Add for large offsets (64-bit pointer arithmetic)
      let const_vreg = ctx.vcode_func.new_vreg(Int)
      let load_const = @instr.VCodeInst::new(LoadConst(end_offset))
      load_const.add_def({ reg: Virtual(const_vreg) })
      block.add_inst(load_const)
      let add_inst = @instr.VCodeInst::new(Add(true))
      add_inst.add_def({ reg: Virtual(result) })
      add_inst.add_use(Virtual(zero_ext))
      add_inst.add_use(Virtual(const_vreg))
      block.add_inst(add_inst)
    }
    result
  } else {
    zero_ext
  }

  // Step 3: Load memory_size from vmctx
  let memory_size = ctx.vcode_func.new_vreg(Int)
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }
  let load_size = @instr.VCodeInst::new(
    LoadPtr(@instr.I64, @abi.VMCTX_MEMORY_SIZE_OFFSET),
  )
  load_size.add_def({ reg: Virtual(memory_size) })
  load_size.add_use(Physical(vmctx_preg))
  block.add_inst(load_size)

  // Step 4: Emit TrapIfUgt - trap if end_addr > memory_size
  let trap_inst = @instr.VCodeInst::new(TrapIfUgt(1)) // trap code 1 = out of bounds
  trap_inst.add_use(Virtual(end_addr))
  trap_inst.add_use(Virtual(memory_size))
  block.add_inst(trap_inst)
}

///|
/// Emit instruction to load memory_base from vmctx on-demand (Cranelift-style)
/// Returns a virtual register containing memory_base
/// This is called before memory operations to get the current memory base address
fn emit_load_memory_base(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
) -> @abi.VReg {
  let memory_base_vreg = ctx.vcode_func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(
    Load(I64, @abi.VMCTX_MEMORY_BASE_OFFSET),
  )
  load_inst.add_def({ reg: Virtual(memory_base_vreg) })
  load_inst.add_use(Physical({ index: @abi.REG_VMCTX, class: Int })) // X19 = vmctx
  block.add_inst(load_inst)
  memory_base_vreg
}

///|
/// Emit instruction to load func_table from vmctx on-demand (Cranelift-style)
/// Returns a virtual register containing func_table pointer
/// This is called before function calls to get the function table base address
fn emit_load_func_table(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
) -> @abi.VReg {
  let func_table_vreg = ctx.vcode_func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(Load(I64, @abi.VMCTX_FUNC_TABLE_OFFSET))
  load_inst.add_def({ reg: Virtual(func_table_vreg) })
  load_inst.add_use(Physical({ index: @abi.REG_VMCTX, class: Int })) // X19 = vmctx
  block.add_inst(load_inst)
  func_table_vreg
}

///|
/// Emit instruction to load table0_base from vmctx on-demand (Cranelift-style)
/// Returns a virtual register containing table0_base pointer
/// This is called before indirect calls to get the indirect table base address
fn emit_load_table0_base(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
) -> @abi.VReg {
  let table0_base_vreg = ctx.vcode_func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(
    Load(I64, @abi.VMCTX_TABLE0_BASE_OFFSET),
  )
  load_inst.add_def({ reg: Virtual(table0_base_vreg) })
  load_inst.add_use(Physical({ index: @abi.REG_VMCTX, class: Int })) // X19 = vmctx
  block.add_inst(load_inst)
  table0_base_vreg
}

///|
/// Lower GetFuncRef - get tagged function pointer for storing in tables
/// Returns func_ptr | FUNCREF_TAG (bit 61) for ref.test detection
fn lower_get_func_ref(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  func_idx : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Step 1: Load func_table pointer from vmctx
  let func_table_vreg = emit_load_func_table(ctx, block)

  // Step 2: Load func_ptr from func_table[func_idx * 8]
  let raw_func_ptr = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(Load(I64, func_idx * 8))
  load_ptr.add_def({ reg: Virtual(raw_func_ptr) })
  load_ptr.add_use(Virtual(func_table_vreg))
  block.add_inst(load_ptr)

  // Step 3: OR with FUNCREF_TAG (0x2000000000000000)
  let tag_vreg = ctx.vcode_func.new_vreg(Int)
  let load_tag = @instr.VCodeInst::new(LoadConst(0x2000000000000000L))
  load_tag.add_def({ reg: Virtual(tag_vreg) })
  block.add_inst(load_tag)
  let or_inst = @instr.VCodeInst::new(Or)
  or_inst.add_def({ reg: Virtual(result_vreg) })
  or_inst.add_use(Virtual(raw_func_ptr))
  or_inst.add_use(Virtual(tag_vreg))
  block.add_inst(or_inst)
}

///|
/// Lower load instruction
/// For WASM, addr is an offset within linear memory, so we need to add memory_base
/// Memory_base is loaded on-demand from vmctx (Cranelift-style)
fn lower_load(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  ty : @ir.Type,
  offset : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let wasm_addr = ctx.get_vreg_for_use(inst.operands[0], block)
    // Determine access size for bounds check
    let mem_ty = ir_type_to_mem_type(ty)
    let access_size = mem_type_size(mem_ty)
    // Emit bounds check: trap if wasm_addr + offset + access_size > memory_size
    emit_bounds_check(ctx, block, wasm_addr, offset, access_size)
    // Load memory_base from vmctx on-demand
    let memory_base = emit_load_memory_base(ctx, block)
    // Compute effective address: memory_base + wasm_addr (64-bit pointer arithmetic)
    let effective_addr = ctx.vcode_func.new_vreg(Int)
    let add_inst = @instr.VCodeInst::new(Add(true))
    add_inst.add_def({ reg: Virtual(effective_addr) })
    add_inst.add_use(Virtual(memory_base))
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
      // Add offset to effective_addr using immediate add (64-bit pointer arithmetic)
      let addr_with_offset = ctx.vcode_func.new_vreg(Int)
      let offset_add = @instr.VCodeInst::new(AddImm(offset, true))
      offset_add.add_def({ reg: Virtual(addr_with_offset) })
      offset_add.add_use(Virtual(effective_addr))
      block.add_inst(offset_add)
      // Now load with offset=0
      let vcode_inst = @instr.VCodeInst::new(Load(mem_ty, 0))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(addr_with_offset))
      block.add_inst(vcode_inst)
    } else {
      // Offset can be encoded directly in the load instruction
      let vcode_inst = @instr.VCodeInst::new(Load(mem_ty, offset))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(effective_addr))
      block.add_inst(vcode_inst)
    }
  }
}

///|
/// Lower store instruction
/// For WASM, addr is an offset within linear memory, so we need to add memory_base
/// Memory_base is loaded on-demand from vmctx (Cranelift-style)
fn lower_store(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
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
  // Load memory_base from vmctx on-demand
  let memory_base = emit_load_memory_base(ctx, block)
  // Compute effective address: memory_base + wasm_addr (64-bit pointer arithmetic)
  let effective_addr = ctx.vcode_func.new_vreg(Int)
  let add_inst = @instr.VCodeInst::new(Add(true))
  add_inst.add_def({ reg: Virtual(effective_addr) })
  add_inst.add_use(Virtual(memory_base))
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
    // Add offset to effective_addr using immediate add (64-bit pointer arithmetic)
    let addr_with_offset = ctx.vcode_func.new_vreg(Int)
    let offset_add = @instr.VCodeInst::new(AddImm(offset, true))
    offset_add.add_def({ reg: Virtual(addr_with_offset) })
    offset_add.add_use(Virtual(effective_addr))
    block.add_inst(offset_add)
    // Now store with offset=0
    let vcode_inst = @instr.VCodeInst::new(Store(mem_ty, 0))
    vcode_inst.add_use(Virtual(addr_with_offset))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  } else {
    // Offset can be encoded directly in the store instruction
    let vcode_inst = @instr.VCodeInst::new(Store(mem_ty, offset))
    vcode_inst.add_use(Virtual(effective_addr))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower narrow load instruction (8/16/32-bit with sign/zero extension)
/// For WASM, addr is an offset within linear memory, so we need to add memory_base
/// Memory_base is loaded on-demand from vmctx (Cranelift-style)
fn lower_load_narrow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  offset : Int,
  opcode_fn : (Int) -> @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
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
    // Load memory_base from vmctx on-demand
    let memory_base = emit_load_memory_base(ctx, block)
    // Compute effective address: memory_base + wasm_addr (64-bit pointer arithmetic)
    let effective_addr = ctx.vcode_func.new_vreg(Int)
    let add_inst = @instr.VCodeInst::new(Add(true))
    add_inst.add_def({ reg: Virtual(effective_addr) })
    add_inst.add_use(Virtual(memory_base))
    add_inst.add_use(Virtual(wasm_addr))
    block.add_inst(add_inst)
    // Check alignment requirement based on opcode type
    // Load8: any offset ok (1-byte aligned)
    // Load16: offset must be 2-aligned for immediate encoding
    // Load32: offset must be 4-aligned for immediate encoding
    let alignment = access_size
    // If offset is not aligned or too large, add it to the address first
    if offset != 0 && (offset % alignment != 0 || offset > 4095 * alignment) {
      // Add offset to effective_addr using immediate add (64-bit pointer arithmetic)
      let addr_with_offset = ctx.vcode_func.new_vreg(Int)
      let offset_add = @instr.VCodeInst::new(AddImm(offset, true))
      offset_add.add_def({ reg: Virtual(addr_with_offset) })
      offset_add.add_use(Virtual(effective_addr))
      block.add_inst(offset_add)
      // Now load with offset=0
      let vcode_inst = @instr.VCodeInst::new(opcode_fn(0))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(addr_with_offset))
      block.add_inst(vcode_inst)
    } else {
      // Offset can be encoded directly in the load instruction
      let vcode_inst = @instr.VCodeInst::new(opcode_fn(offset))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(effective_addr))
      block.add_inst(vcode_inst)
    }
  }
}

///|
/// Lower narrow store instruction (8/16/32-bit)
/// For WASM, addr is an offset within linear memory, so we need to add memory_base
/// Memory_base is loaded on-demand from vmctx (Cranelift-style)
fn lower_store_narrow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  offset : Int,
  mem_ty : @instr.MemType,
) -> Unit {
  // Store has no result, just uses: addr, value
  let wasm_addr = ctx.get_vreg_for_use(inst.operands[0], block)
  let value = ctx.get_vreg_for_use(inst.operands[1], block)
  // Determine access size for bounds check
  let access_size = mem_type_size(mem_ty)
  // Emit bounds check: trap if wasm_addr + offset + access_size > memory_size
  emit_bounds_check(ctx, block, wasm_addr, offset, access_size)
  // Load memory_base from vmctx on-demand
  let memory_base = emit_load_memory_base(ctx, block)
  // Compute effective address: memory_base + wasm_addr (64-bit pointer arithmetic)
  let effective_addr = ctx.vcode_func.new_vreg(Int)
  let add_inst = @instr.VCodeInst::new(Add(true))
  add_inst.add_def({ reg: Virtual(effective_addr) })
  add_inst.add_use(Virtual(memory_base))
  add_inst.add_use(Virtual(wasm_addr))
  block.add_inst(add_inst)
  // Check alignment requirement based on memory type
  let alignment = access_size
  // If offset is not aligned or too large, add it to the address first
  if offset != 0 && (offset % alignment != 0 || offset > 4095 * alignment) {
    // Add offset to effective_addr using immediate add (64-bit pointer arithmetic)
    let addr_with_offset = ctx.vcode_func.new_vreg(Int)
    let offset_add = @instr.VCodeInst::new(AddImm(offset, true))
    offset_add.add_def({ reg: Virtual(addr_with_offset) })
    offset_add.add_use(Virtual(effective_addr))
    block.add_inst(offset_add)
    // Now store with offset=0
    let vcode_inst = @instr.VCodeInst::new(Store(mem_ty, 0))
    vcode_inst.add_use(Virtual(addr_with_offset))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  } else {
    // Offset can be encoded directly in the store instruction
    let vcode_inst = @instr.VCodeInst::new(Store(mem_ty, offset))
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
  block : @block.VCodeBlock,
  signed~ : Bool,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    // Determine the extend kind based on source and destination types
    let src_ty = inst.operands[0].ty
    let dst_ty = result.ty
    let kind = get_extend_kind(src_ty, dst_ty, signed)
    let vcode_inst = @instr.VCodeInst::new(Extend(kind))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower in-place sign extension (Sextend8, Sextend16, Sextend32)
/// These operations sign-extend the low N bits to fill the full register
fn lower_sextend_inplace(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  from_bits~ : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let dst_ty = result.ty
    let is_i64 = dst_ty is @ir.Type::I64
    // Determine extend kind based on source bits and destination type
    let kind : @instr.ExtendKind = match (from_bits, is_i64) {
      (8, false) => Signed8To32
      (8, true) => Signed8To64
      (16, false) => Signed16To32
      (16, true) => Signed16To64
      (32, _) => Signed32To64 // 32-bit extend is always to 64-bit
      _ => Signed8To32 // fallback
    }
    let vcode_inst = @instr.VCodeInst::new(Extend(kind))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Determine the extend kind based on source and destination types
fn get_extend_kind(
  src_ty : @ir.Type,
  dst_ty : @ir.Type,
  signed : Bool,
) -> @instr.ExtendKind {
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
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(Truncate)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower float to int conversion (trapping version)
/// Cranelift-style lowering: expand to multiple primitive instructions
///
/// Generated sequence:
/// 1. FpuCmp(src, src) - compare with self to check for NaN
/// 2. TrapIf(Vs, 3) - trap if NaN (V flag set for unordered)
/// 3. tmp_min = LoadConstF32/F64(min_bound)
/// 4. FpuCmp(src, tmp_min) - compare with minimum
/// 5. TrapIf(Le/Lt, 3) - trap if underflow
/// 6. tmp_max = LoadConstF32/F64(max_bound)
/// 7. FpuCmp(src, tmp_max) - compare with maximum
/// 8. TrapIf(Ge, 3) - trap if overflow
/// 9. dst = FcvtToInt(src) - raw conversion
fn lower_float_to_int(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  signed~ : Bool,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  let src_ty = inst.operands[0].ty
  let dst_ty = result.ty
  let is_f32 = src_ty is @ir.Type::F32
  let is_i64 = dst_ty is @ir.Type::I64
  let float_class : @abi.RegClass = if is_f32 { Float32 } else { Float64 }

  // Step 1: NaN check - FpuCmp(src, src)
  // NaN != NaN sets V flag (unordered)
  let nan_check = @instr.VCodeInst::new(FpuCmp(is_f32))
  nan_check.add_use(Virtual(src))
  nan_check.add_use(Virtual(src))
  block.add_inst(nan_check)

  // Step 2: TrapIf(Vs) - trap if NaN
  let trap_nan = @instr.VCodeInst::new(TrapIf(@instr.Vs, 3))
  block.add_inst(trap_nan)

  // Get bounds based on conversion type
  let (min_bits, max_bits, use_le_for_min) = get_float_to_int_bounds(
    is_f32, is_i64, signed,
  )

  // Step 3: Load minimum bound
  let tmp_min = ctx.vcode_func.new_vreg(float_class)
  let load_min = if is_f32 {
    @instr.VCodeInst::new(LoadConstF32(min_bits.to_int()))
  } else {
    @instr.VCodeInst::new(LoadConstF64(min_bits))
  }
  load_min.add_def({ reg: Virtual(tmp_min) })
  block.add_inst(load_min)

  // Step 4: FpuCmp(src, tmp_min)
  let cmp_min = @instr.VCodeInst::new(FpuCmp(is_f32))
  cmp_min.add_use(Virtual(src))
  cmp_min.add_use(Virtual(tmp_min))
  block.add_inst(cmp_min)

  // Step 5: TrapIf for underflow
  // For signed: trap if src < min (Lt)
  // For unsigned: trap if src <= -1.0 (Le)
  let trap_min_cond = if use_le_for_min {
    @instr.Cond::Le
  } else {
    @instr.Cond::Lt
  }
  let trap_min = @instr.VCodeInst::new(TrapIf(trap_min_cond, 3))
  block.add_inst(trap_min)

  // Step 6: Load maximum bound
  let tmp_max = ctx.vcode_func.new_vreg(float_class)
  let load_max = if is_f32 {
    @instr.VCodeInst::new(LoadConstF32(max_bits.to_int()))
  } else {
    @instr.VCodeInst::new(LoadConstF64(max_bits))
  }
  load_max.add_def({ reg: Virtual(tmp_max) })
  block.add_inst(load_max)

  // Step 7: FpuCmp(src, tmp_max)
  let cmp_max = @instr.VCodeInst::new(FpuCmp(is_f32))
  cmp_max.add_use(Virtual(src))
  cmp_max.add_use(Virtual(tmp_max))
  block.add_inst(cmp_max)

  // Step 8: TrapIf(Ge) for overflow - trap if src >= max
  let trap_max = @instr.VCodeInst::new(TrapIf(@instr.Cond::Ge, 3))
  block.add_inst(trap_max)

  // Step 9: FcvtToInt - raw conversion (no checks)
  let fcvt = @instr.VCodeInst::new(FcvtToInt(is_f32, is_i64, signed))
  fcvt.add_def({ reg: Virtual(dst) })
  fcvt.add_use(Virtual(src))
  block.add_inst(fcvt)
}

///|
/// Get bounds for float-to-int conversion
/// Returns (min_bits, max_bits, use_le_for_min)
/// - min_bits: bit representation of minimum bound
/// - max_bits: bit representation of maximum bound
/// - use_le_for_min: true if should use Le (<=) for underflow check, false for Lt (<)
fn get_float_to_int_bounds(
  is_f32 : Bool,
  is_i64 : Bool,
  signed : Bool,
) -> (Int64, Int64, Bool) {
  match (is_f32, is_i64, signed) {
    // F32 conversions
    (true, false, true) =>
      // F32ToI32S: min = -2^31 = 0xCF000000, max = 2^31 = 0x4F000000
      (0xCF000000L, 0x4F000000L, false)
    (true, false, false) =>
      // F32ToI32U: min = -1.0 = 0xBF800000 (trap if <= -1), max = 2^32 = 0x4F800000
      (0xBF800000L, 0x4F800000L, true)
    (true, true, true) =>
      // F32ToI64S: min = -2^63 = 0xDF000000, max = 2^63 = 0x5F000000
      (0xDF000000L, 0x5F000000L, false)
    (true, true, false) =>
      // F32ToI64U: min = -1.0 = 0xBF800000 (trap if <= -1), max = 2^64 = 0x5F800000
      (0xBF800000L, 0x5F800000L, true)
    // F64 conversions
    (false, false, true) =>
      // F64ToI32S: min = -2^31-1 = 0xC1E0000000200000, max = 2^31 = 0x41E0000000000000
      (0xC1E0000000200000L, 0x41E0000000000000L, true)
    (false, false, false) =>
      // F64ToI32U: min = -1.0 = 0xBFF0000000000000 (trap if <= -1), max = 2^32 = 0x41F0000000000000
      (0xBFF0000000000000L, 0x41F0000000000000L, true)
    (false, true, true) =>
      // F64ToI64S: min = -2^63 = 0xC3E0000000000000, max = 2^63 = 0x43E0000000000000
      (0xC3E0000000000000L, 0x43E0000000000000L, false)
    (false, true, false) =>
      // F64ToI64U: min = -1.0 = 0xBFF0000000000000 (trap if <= -1), max = 2^64 = 0x43F0000000000000
      (0xBFF0000000000000L, 0x43F0000000000000L, true)
  }
}

///|
/// Lower saturating float to int conversion
/// AArch64 FCVTZS/FCVTZU already handles saturation correctly:
/// - NaN → 0
/// - Overflow → clamp to min/max
/// So we just emit a single FcvtToInt instruction.
fn lower_float_to_int_sat(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  signed~ : Bool,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  let src_ty = inst.operands[0].ty
  let dst_ty = result.ty
  let is_f32 = src_ty is @ir.Type::F32
  let is_i64 = dst_ty is @ir.Type::I64

  // AArch64 FCVTZS/FCVTZU already implements WebAssembly saturating semantics
  let fcvt = @instr.VCodeInst::new(FcvtToInt(is_f32, is_i64, signed))
  fcvt.add_def({ reg: Virtual(dst) })
  fcvt.add_use(Virtual(src))
  block.add_inst(fcvt)
}

///|
/// Lower int to float conversion
fn lower_int_to_float(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  signed~ : Bool,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    // Determine conversion kind based on source/dest types and signedness
    let src_ty = inst.operands[0].ty
    let dst_ty = result.ty
    let kind : @instr.IntToFloatKind = match (src_ty, dst_ty, signed) {
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
    let vcode_inst = @instr.VCodeInst::new(IntToFloat(kind))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower copy instruction
fn lower_copy(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(Move)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower select instruction (cond ? true_val : false_val)
/// Uses AArch64 CSEL instruction: if cond != 0, select true_val, else false_val
fn lower_select(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let cond = ctx.get_vreg_for_use(inst.operands[0], block)
    let true_val = ctx.get_vreg_for_use(inst.operands[1], block)
    let false_val = ctx.get_vreg_for_use(inst.operands[2], block)

    // Emit Select instruction: dst = cond != 0 ? true_val : false_val
    let vcode_inst = @instr.VCodeInst::new(Select)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(cond))
    vcode_inst.add_use(Virtual(true_val))
    vcode_inst.add_use(Virtual(false_val))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower a terminator
fn lower_terminator(
  ctx : LoweringContext,
  term : @ir.Terminator,
  block : @block.VCodeBlock,
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
              let mov_inst = @instr.VCodeInst::new(Move)
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
      let regs : Array[@abi.Reg] = []
      for v in values {
        regs.push(Virtual(ctx.get_vreg_for_use(v, block)))
      }
      block.set_terminator(Return(regs))
    }
    @ir.Terminator::Trap(msg) => block.set_terminator(Trap(msg))
    @ir.Terminator::BrTable(index, targets, default) => {
      let index_vreg = ctx.get_vreg_for_use(index, block)
      let default_id = ctx.get_block_id(default)
      // WebAssembly br_table index is i32, but check IR type to be safe
      let is_64 = index.ty is @ir.Type::I64
      if targets.is_empty() {
        // No targets, just jump to default
        block.set_terminator(Jump(default_id))
      } else if targets.length() < 4 {
        // Small number of targets: use comparison chain (more efficient)
        let chain_blocks : Array[@block.VCodeBlock] = []
        for _ in 0..<(targets.length() - 1) {
          chain_blocks.push(ctx.vcode_func.new_block())
        }

        // First comparison in original block
        let cmp_result_0 = ctx.vcode_func.new_vreg(Int)
        let zero_vreg = ctx.vcode_func.new_vreg(Int)
        let load_zero = @instr.VCodeInst::new(LoadConst(0L))
        load_zero.add_def({ reg: Virtual(zero_vreg) })
        block.add_inst(load_zero)
        let cmp_inst_0 = @instr.VCodeInst::new(Cmp(Eq, is_64))
        cmp_inst_0.add_def({ reg: Virtual(cmp_result_0) })
        cmp_inst_0.add_use(Virtual(index_vreg))
        cmp_inst_0.add_use(Virtual(zero_vreg))
        block.add_inst(cmp_inst_0)
        let target_0_id = ctx.get_block_id(targets[0])
        if targets.length() == 1 {
          block.set_terminator(
            Branch(Virtual(cmp_result_0), target_0_id, default_id),
          )
        } else {
          block.set_terminator(
            Branch(Virtual(cmp_result_0), target_0_id, chain_blocks[0].id),
          )
        }

        // Chain blocks for remaining targets
        for i in 1..<targets.length() {
          let chain_block = chain_blocks[i - 1]
          let target_id = ctx.get_block_id(targets[i])
          let const_vreg = ctx.vcode_func.new_vreg(Int)
          let load_const = @instr.VCodeInst::new(LoadConst(i.to_int64()))
          load_const.add_def({ reg: Virtual(const_vreg) })
          chain_block.add_inst(load_const)
          let cmp_result = ctx.vcode_func.new_vreg(Int)
          let cmp_inst = @instr.VCodeInst::new(Cmp(Eq, is_64))
          cmp_inst.add_def({ reg: Virtual(cmp_result) })
          cmp_inst.add_use(Virtual(index_vreg))
          cmp_inst.add_use(Virtual(const_vreg))
          chain_block.add_inst(cmp_inst)
          if i == targets.length() - 1 {
            chain_block.set_terminator(
              Branch(Virtual(cmp_result), target_id, default_id),
            )
          } else {
            chain_block.set_terminator(
              Branch(Virtual(cmp_result), target_id, chain_blocks[i].id),
            )
          }
        }
      } else {
        // Large number of targets: use jump table (O(1) dispatch)
        let target_ids : Array[Int] = []
        for target in targets {
          target_ids.push(ctx.get_block_id(target))
        }
        block.set_terminator(
          BrTable(Virtual(index_vreg), target_ids, default_id),
        )
      }
    }
  }
}

///|
/// Lower a direct function call
/// Generates code to:
/// 1. Load func_table from vmctx on-demand
/// 2. Load the function pointer from the function table
/// 3. Call through the function pointer with arguments
fn lower_call(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  func_idx : Int,
) -> Unit {
  // Collect argument vregs
  let arg_vregs : Array[@abi.VReg] = []
  for operand in inst.operands {
    arg_vregs.push(ctx.get_vreg_for_use(operand, block))
  }

  // Get all result vregs
  let result_vregs : Array[@abi.VReg] = []
  for result in inst.all_results() {
    result_vregs.push(ctx.get_vreg(result))
  }

  // Load func_table from vmctx on-demand
  let func_table = emit_load_func_table(ctx, block)

  // Load function pointer from table: func_ptr = [func_table + func_idx * 8]
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let offset = func_idx * 8
  let load_inst = @instr.VCodeInst::new(Load(I64, offset))
  load_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  load_inst.add_use(Virtual(func_table))
  block.add_inst(load_inst)

  // Use Cranelift-style call lowering
  lower_wasm_call(ctx, block, func_ptr_vreg, arg_vregs, result_vregs)
}

///|
/// Lower memory.grow instruction
/// memory.grow takes a delta (number of pages to grow) and returns the previous size or -1
fn lower_memory_grow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  max_pages : Int?,
) -> Unit {
  // Get the delta operand
  let delta_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Create the MemoryGrow VCode instruction
  // Uses: [delta], Defs: [result]
  // Convert Int? to Int (0 = no limit)
  let max_pages_value = max_pages.unwrap_or(0)
  let grow_inst = @instr.VCodeInst::new(MemoryGrow(max_pages_value))
  grow_inst.add_def({ reg: Virtual(result_vreg) })
  grow_inst.add_use(Virtual(delta_vreg))
  // Add clobbers for caller-saved registers (it's a call)
  add_call_clobbers(grow_inst)
  // Also clobber X19 since emit uses it as temp to save result across internal calls
  grow_inst.add_def({ reg: Physical({ index: 19, class: Int }) })
  block.add_inst(grow_inst)
}

///|
/// Lower memory.size instruction
/// memory.size returns the current memory size in pages
fn lower_memory_size(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Create the MemorySize VCode instruction
  // Uses: [], Defs: [result]
  let size_inst = @instr.VCodeInst::new(MemorySize)
  size_inst.add_def({ reg: Virtual(result_vreg) })
  // Add clobbers for caller-saved registers (it's a call)
  add_call_clobbers(size_inst)
  block.add_inst(size_inst)
}

///|
/// Lower memory.fill instruction
/// memory.fill fills a memory region with a byte value
fn lower_memory_fill(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  // Get the operands: dst, val, size
  guard inst.operands.length() >= 3 else { return }
  let dst = ctx.get_vreg_for_use(inst.operands[0], block)
  let val = ctx.get_vreg_for_use(inst.operands[1], block)
  let size = ctx.get_vreg_for_use(inst.operands[2], block)

  // Create the MemoryFill VCode instruction
  // Uses: [dst, val, size], Defs: []
  let fill_inst = @instr.VCodeInst::new(MemoryFill)
  fill_inst.add_use(Virtual(dst))
  fill_inst.add_use(Virtual(val))
  fill_inst.add_use(Virtual(size))
  // Only clobber registers actually used by codegen: x0-x2 (args), x16 (func ptr)
  // Don't clobber all caller-saved regs to avoid breaking value reuse
  fill_inst.add_def({ reg: Physical({ index: 0, class: Int }) }) // x0
  fill_inst.add_def({ reg: Physical({ index: 1, class: Int }) }) // x1
  fill_inst.add_def({ reg: Physical({ index: 2, class: Int }) }) // x2
  fill_inst.add_def({ reg: Physical({ index: 16, class: Int }) }) // x16
  block.add_inst(fill_inst)
}

///|
/// Lower memory.copy instruction
/// memory.copy copies a memory region (handles overlapping regions correctly)
fn lower_memory_copy(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  // Get the operands: dst, src, size
  guard inst.operands.length() >= 3 else { return }
  let dst = ctx.get_vreg_for_use(inst.operands[0], block)
  let src = ctx.get_vreg_for_use(inst.operands[1], block)
  let size = ctx.get_vreg_for_use(inst.operands[2], block)

  // Create the MemoryCopy VCode instruction
  // Uses: [dst, src, size], Defs: []
  let copy_inst = @instr.VCodeInst::new(MemoryCopy)
  copy_inst.add_use(Virtual(dst))
  copy_inst.add_use(Virtual(src))
  copy_inst.add_use(Virtual(size))
  // Only clobber registers actually used by codegen: x0-x2 (args), x16 (func ptr)
  // Don't clobber all caller-saved regs to avoid breaking value reuse
  copy_inst.add_def({ reg: Physical({ index: 0, class: Int }) }) // x0
  copy_inst.add_def({ reg: Physical({ index: 1, class: Int }) }) // x1
  copy_inst.add_def({ reg: Physical({ index: 2, class: Int }) }) // x2
  copy_inst.add_def({ reg: Physical({ index: 16, class: Int }) }) // x16
  block.add_inst(copy_inst)
}

///|
/// Lower table.get instruction
/// Loads a function reference from the indirect table
///
/// Cranelift-style lowering: expand to primitive instructions here
/// instead of deferring to emit phase with hardcoded registers.
///
/// Generated sequence:
/// 1. elem_idx_64 = Extend(elem_idx, Unsigned32To64) // zero-extend 32->64
/// 2. table_size = LoadPtr(I64, VMCTX_TABLE0_ELEMENTS_OFFSET) from vmctx
/// 3. TrapIfUge(elem_idx_64, table_size, 1) // trap if out of bounds
/// 4. table_base = LoadPtr(I64, VMCTX_TABLE0_BASE_OFFSET) from vmctx (X19)
/// 5. addr = AddShifted(table_base, elem_idx_64, Lsl, 4)  // addr = table_base + elem_idx * 16
/// 6. result = LoadPtr(I64, 0) from addr
fn lower_table_get(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  table_idx : Int,
) -> Unit {
  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Get the element index operand
  guard inst.operands.length() > 0 else { return }
  let elem_idx = ctx.get_vreg_for_use(inst.operands[0], block)

  // Step 1: Zero-extend elem_idx from 32-bit to 64-bit
  let elem_idx_64 = ctx.new_vreg(@abi.Int)
  let extend_inst = @instr.VCodeInst::new(Extend(Unsigned32To64))
  extend_inst.add_def({ reg: Virtual(elem_idx_64) })
  extend_inst.add_use(Virtual(elem_idx))
  block.add_inst(extend_inst)
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }

  // Load table_size and table_base depending on table_idx
  let table_size = ctx.new_vreg(@abi.Int)
  let table_base = ctx.new_vreg(@abi.Int)
  if table_idx == 0 {
    // Fast path for table 0
    // Step 2: Load table_size from vmctx
    let load_size = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE0_ELEMENTS_OFFSET),
    )
    load_size.add_use(Physical(vmctx_preg))
    load_size.add_def({ reg: Virtual(table_size) })
    block.add_inst(load_size)

    // Step 4: Load table0_base from vmctx
    let load_table = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE0_BASE_OFFSET),
    )
    load_table.add_use(Physical(vmctx_preg))
    load_table.add_def({ reg: Virtual(table_base) })
    block.add_inst(load_table)
  } else {
    // Multi-table path
    // Load table_sizes array pointer
    let table_sizes_ptr = ctx.new_vreg(@abi.Int)
    let load_sizes_ptr = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE_SIZES_OFFSET),
    )
    load_sizes_ptr.add_use(Physical(vmctx_preg))
    load_sizes_ptr.add_def({ reg: Virtual(table_sizes_ptr) })
    block.add_inst(load_sizes_ptr)

    // Load table_size from table_sizes[table_idx]
    let load_size = @instr.VCodeInst::new(LoadPtr(@instr.I64, table_idx * 8))
    load_size.add_use(Virtual(table_sizes_ptr))
    load_size.add_def({ reg: Virtual(table_size) })
    block.add_inst(load_size)

    // Load tables array pointer
    let tables_ptr = ctx.new_vreg(@abi.Int)
    let load_tables_ptr = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLES_OFFSET),
    )
    load_tables_ptr.add_use(Physical(vmctx_preg))
    load_tables_ptr.add_def({ reg: Virtual(tables_ptr) })
    block.add_inst(load_tables_ptr)

    // Load table_base from tables[table_idx]
    let load_table = @instr.VCodeInst::new(LoadPtr(@instr.I64, table_idx * 8))
    load_table.add_use(Virtual(tables_ptr))
    load_table.add_def({ reg: Virtual(table_base) })
    block.add_inst(load_table)
  }

  // Step 3: Bounds check - trap if elem_idx >= table_size
  let trap_inst = @instr.VCodeInst::new(TrapIfUge(1)) // trap code 1 = out of bounds
  trap_inst.add_use(Virtual(elem_idx_64))
  trap_inst.add_use(Virtual(table_size))
  block.add_inst(trap_inst)

  // Step 5: Calculate address: addr = table_base + (elem_idx << 4)
  // Each table element is 16 bytes (func_ptr + type_idx)
  let addr = ctx.new_vreg(@abi.Int)
  let calc_addr = @instr.VCodeInst::new(AddShifted(@instr.Lsl, 4))
  calc_addr.add_use(Virtual(table_base))
  calc_addr.add_use(Virtual(elem_idx_64))
  calc_addr.add_def({ reg: Virtual(addr) })
  block.add_inst(calc_addr)

  // Step 6: Load result from addr
  let load_result = @instr.VCodeInst::new(LoadPtr(@instr.I64, 0))
  load_result.add_use(Virtual(addr))
  load_result.add_def({ reg: Virtual(result_vreg) })
  block.add_inst(load_result)
}

///|
/// Lower table.set instruction
/// Stores a function reference to the indirect table
///
/// Cranelift-style lowering: expand to primitive instructions here
/// instead of deferring to emit phase with hardcoded registers.
///
/// Generated sequence:
/// 1. elem_idx_64 = Extend(elem_idx, Unsigned32To64) // zero-extend 32->64
/// 2. table_size = LoadPtr(I64, VMCTX_TABLE0_ELEMENTS_OFFSET) from vmctx
/// 3. TrapIfUge(elem_idx_64, table_size, 1) // trap if out of bounds
/// 4. table_base = LoadPtr(I64, VMCTX_TABLE0_BASE_OFFSET) from vmctx (X19)
/// 5. addr = AddShifted(table_base, elem_idx_64, Lsl, 4)  // addr = table_base + elem_idx * 16
/// 6. StorePtr(I64, 0) value to addr
fn lower_table_set(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  table_idx : Int,
) -> Unit {
  // Get the operands: elem_idx and value
  guard inst.operands.length() >= 2 else { return }
  let elem_idx = ctx.get_vreg_for_use(inst.operands[0], block)
  let value = ctx.get_vreg_for_use(inst.operands[1], block)

  // Step 1: Zero-extend elem_idx from 32-bit to 64-bit
  let elem_idx_64 = ctx.new_vreg(@abi.Int)
  let extend_inst = @instr.VCodeInst::new(Extend(Unsigned32To64))
  extend_inst.add_def({ reg: Virtual(elem_idx_64) })
  extend_inst.add_use(Virtual(elem_idx))
  block.add_inst(extend_inst)
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }

  // Load table_size and table_base depending on table_idx
  let table_size = ctx.new_vreg(@abi.Int)
  let table_base = ctx.new_vreg(@abi.Int)
  if table_idx == 0 {
    // Fast path for table 0
    // Step 2: Load table_size from vmctx
    let load_size = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE0_ELEMENTS_OFFSET),
    )
    load_size.add_use(Physical(vmctx_preg))
    load_size.add_def({ reg: Virtual(table_size) })
    block.add_inst(load_size)

    // Step 4: Load table0_base from vmctx
    let load_table = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE0_BASE_OFFSET),
    )
    load_table.add_use(Physical(vmctx_preg))
    load_table.add_def({ reg: Virtual(table_base) })
    block.add_inst(load_table)
  } else {
    // Multi-table path
    // Load table_sizes array pointer
    let table_sizes_ptr = ctx.new_vreg(@abi.Int)
    let load_sizes_ptr = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE_SIZES_OFFSET),
    )
    load_sizes_ptr.add_use(Physical(vmctx_preg))
    load_sizes_ptr.add_def({ reg: Virtual(table_sizes_ptr) })
    block.add_inst(load_sizes_ptr)

    // Load table_size from table_sizes[table_idx]
    let load_size = @instr.VCodeInst::new(LoadPtr(@instr.I64, table_idx * 8))
    load_size.add_use(Virtual(table_sizes_ptr))
    load_size.add_def({ reg: Virtual(table_size) })
    block.add_inst(load_size)

    // Load tables array pointer
    let tables_ptr = ctx.new_vreg(@abi.Int)
    let load_tables_ptr = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLES_OFFSET),
    )
    load_tables_ptr.add_use(Physical(vmctx_preg))
    load_tables_ptr.add_def({ reg: Virtual(tables_ptr) })
    block.add_inst(load_tables_ptr)

    // Load table_base from tables[table_idx]
    let load_table = @instr.VCodeInst::new(LoadPtr(@instr.I64, table_idx * 8))
    load_table.add_use(Virtual(tables_ptr))
    load_table.add_def({ reg: Virtual(table_base) })
    block.add_inst(load_table)
  }

  // Step 3: Bounds check - trap if elem_idx >= table_size
  let trap_inst = @instr.VCodeInst::new(TrapIfUge(1)) // trap code 1 = out of bounds
  trap_inst.add_use(Virtual(elem_idx_64))
  trap_inst.add_use(Virtual(table_size))
  block.add_inst(trap_inst)

  // Step 5: Calculate address: addr = table_base + (elem_idx << 4)
  // Each table element is 16 bytes (func_ptr + type_idx)
  let addr = ctx.new_vreg(@abi.Int)
  let calc_addr = @instr.VCodeInst::new(AddShifted(@instr.Lsl, 4))
  calc_addr.add_use(Virtual(table_base))
  calc_addr.add_use(Virtual(elem_idx_64))
  calc_addr.add_def({ reg: Virtual(addr) })
  block.add_inst(calc_addr)

  // Step 6: Store value to addr
  let store_value = @instr.VCodeInst::new(StorePtr(@instr.I64, 0))
  store_value.add_use(Virtual(addr))
  store_value.add_use(Virtual(value))
  block.add_inst(store_value)
}

///|
/// Lower table.size instruction
/// Returns the current number of elements in the table
///
/// Generated sequence (for table 0):
/// 1. result = LoadPtr(I64, VMCTX_TABLE0_ELEMENTS_OFFSET) from vmctx
/// Generated sequence (for table N > 0):
/// 1. table_sizes_ptr = LoadPtr(I64, VMCTX_TABLE_SIZES_OFFSET) from vmctx
/// 2. result = LoadPtr(I64, table_idx * 8) from table_sizes_ptr
/// Note: Result is returned as 64-bit but high 32 bits are always 0
fn lower_table_size(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  table_idx : Int,
) -> Unit {
  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }
  if table_idx == 0 {
    // Fast path for table 0: load table0_elements from vmctx directly into result
    let load_size = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE0_ELEMENTS_OFFSET),
    )
    load_size.add_use(Physical(vmctx_preg))
    load_size.add_def({ reg: Virtual(result_vreg) })
    block.add_inst(load_size)
  } else {
    // Multi-table path: load from table_sizes array
    // 1. Load table_sizes array pointer: [vmctx + VMCTX_TABLE_SIZES_OFFSET]
    let table_sizes_ptr = ctx.new_vreg(@abi.Int)
    let load_sizes = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE_SIZES_OFFSET),
    )
    load_sizes.add_use(Physical(vmctx_preg))
    load_sizes.add_def({ reg: Virtual(table_sizes_ptr) })
    block.add_inst(load_sizes)

    // 2. Load size for this table: [table_sizes + table_idx * 8]
    // Each size is 8 bytes (size_t)
    let size_offset = table_idx * 8
    let load_size = @instr.VCodeInst::new(LoadPtr(@instr.I64, size_offset))
    load_size.add_use(Virtual(table_sizes_ptr))
    load_size.add_def({ reg: Virtual(result_vreg) })
    block.add_inst(load_size)
  }
}

///|
/// Lower table.grow instruction
/// Grows the table by delta elements, initializing new elements with init_value
/// Returns the previous size (as i32), or -1 if grow failed
///
/// This is a runtime call that goes through the C FFI
fn lower_table_grow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  table_idx : Int,
) -> Unit {
  // Get operands: delta, init_value
  guard inst.operands.length() >= 2 else { return }
  let delta = ctx.get_vreg_for_use(inst.operands[0], block)
  let init_value = ctx.get_vreg_for_use(inst.operands[1], block)

  // Get or create the result vreg
  // Note: We must emit the call even if result is unused because table_grow has side effects
  let result_vreg = match inst.result {
    Some(result) => ctx.get_vreg(result)
    None => ctx.vcode_func.new_vreg(@abi.Int) // Create a temp vreg for the unused result
  }

  // Create the TableGrow VCode instruction
  // Uses: [delta, init_value], Defs: [result]
  let grow_inst = @instr.VCodeInst::new(TableGrow(table_idx))
  grow_inst.add_def({ reg: Virtual(result_vreg) })
  grow_inst.add_use(Virtual(delta))
  grow_inst.add_use(Virtual(init_value))
  // Add clobbers for caller-saved registers (it's a call)
  add_call_clobbers(grow_inst)
  block.add_inst(grow_inst)
}

///|
/// Lower an indirect function call (call_indirect)
/// The callee is already on the stack as a function table index
fn lower_call_indirect(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  expected_type_idx : Int,
  table_idx : Int,
) -> Unit {
  // For call_indirect, the first operand is the element index within the table
  // which we need to convert to a function pointer
  if inst.operands.length() == 0 {
    return
  }

  // First operand is the element index within the specific table
  let elem_idx_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Multi-table support: determine which table pointer to use
  // Both table_idx == 0 and table_idx != 0 load the table pointer on-demand
  // following Cranelift's approach (no pre-loaded registers for table pointers)
  let table_ptr_vreg : @abi.VReg = if table_idx == 0 {
    // Fast path for table 0: load table0_base from vmctx on-demand
    emit_load_table0_base(ctx, block)
  } else {
    // Slow path: load indirect_tables[table_idx] from context
    // 1. Load indirect_tables array pointer: [X19 + 32]
    let indirect_tables_vreg = ctx.vcode_func.new_vreg(Int)
    let load_array_inst = @instr.VCodeInst::new(
      Load(I64, @abi.VMCTX_TABLES_OFFSET),
    )
    load_array_inst.add_def({ reg: Virtual(indirect_tables_vreg) })
    load_array_inst.add_use(Physical({ index: 19, class: Int }))
    block.add_inst(load_array_inst)
    // 2. Calculate offset = table_idx * 8 (pointer size)
    let table_offset = table_idx * 8
    // 3. Load table pointer: [indirect_tables + offset]
    let ptr_vreg = ctx.vcode_func.new_vreg(Int)
    let load_table_inst = @instr.VCodeInst::new(Load(I64, table_offset))
    load_table_inst.add_def({ reg: Virtual(ptr_vreg) })
    load_table_inst.add_use(Virtual(indirect_tables_vreg))
    block.add_inst(load_table_inst)
    ptr_vreg
  }

  // Arguments are all operands except the first one
  let arg_vregs : Array[@abi.VReg] = []
  for i in 1..<inst.operands.length() {
    arg_vregs.push(ctx.get_vreg_for_use(inst.operands[i], block))
  }

  // Get all result vregs
  let result_vregs : Array[@abi.VReg] = []
  for result in inst.all_results() {
    result_vregs.push(ctx.get_vreg(result))
  }

  // Create temporaries for calculation
  let offset_vreg = ctx.vcode_func.new_vreg(Int)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let actual_type_vreg = ctx.vcode_func.new_vreg(Int)

  // Step 1: Calculate offset = elem_idx * 16 (each entry is 16 bytes: func_ptr + type_idx)
  // Use 64-bit multiply since we're working with 64-bit pointers
  let const_16_vreg = ctx.vcode_func.new_vreg(Int)
  let load_16 = @instr.VCodeInst::new(LoadConst(16L))
  load_16.add_def({ reg: Virtual(const_16_vreg) })
  block.add_inst(load_16)
  let mul_inst = @instr.VCodeInst::new(Mul(true))
  mul_inst.add_def({ reg: Virtual(offset_vreg) })
  mul_inst.add_use(Virtual(elem_idx_vreg))
  mul_inst.add_use(Virtual(const_16_vreg))
  block.add_inst(mul_inst)

  // Step 2: Calculate address = table_ptr + offset (64-bit pointer arithmetic)
  // table_ptr is loaded on-demand from vmctx (following Cranelift's approach)
  let addr_vreg = ctx.vcode_func.new_vreg(Int)
  let add_inst = @instr.VCodeInst::new(Add(true))
  add_inst.add_def({ reg: Virtual(addr_vreg) })
  add_inst.add_use(Virtual(table_ptr_vreg))
  add_inst.add_use(Virtual(offset_vreg))
  block.add_inst(add_inst)

  // Step 3: Load function pointer from address (offset 0)
  let raw_func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_func_inst = @instr.VCodeInst::new(Load(I64, 0))
  load_func_inst.add_def({ reg: Virtual(raw_func_ptr_vreg) })
  load_func_inst.add_use(Virtual(addr_vreg))
  block.add_inst(load_func_inst)

  // Step 3.5: Clear FUNCREF_TAG (bit 61) from function pointer
  // Function pointers in tables are tagged with 0x2000000000000000 for ref.test
  // We need to clear this tag before calling: mask = ~0x2000000000000000 = 0xDFFFFFFFFFFFFFFF
  let mask_vreg = ctx.vcode_func.new_vreg(Int)
  let load_mask = @instr.VCodeInst::new(LoadConst(0xDFFFFFFFFFFFFFFFL))
  load_mask.add_def({ reg: Virtual(mask_vreg) })
  block.add_inst(load_mask)
  let and_inst = @instr.VCodeInst::new(And)
  and_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  and_inst.add_use(Virtual(raw_func_ptr_vreg))
  and_inst.add_use(Virtual(mask_vreg))
  block.add_inst(and_inst)

  // Step 4: Load actual type index from address + 8
  let load_type_inst = @instr.VCodeInst::new(Load(I64, 8))
  load_type_inst.add_def({ reg: Virtual(actual_type_vreg) })
  load_type_inst.add_use(Virtual(addr_vreg))
  block.add_inst(load_type_inst)

  // Step 5: Emit type check instruction (traps if types don't match)
  let type_check_inst = @instr.VCodeInst::new(
    TypeCheckIndirect(expected_type_idx),
  )
  type_check_inst.add_use(Virtual(actual_type_vreg))
  block.add_inst(type_check_inst)

  // Step 6: Use Cranelift-style call lowering
  lower_wasm_call(ctx, block, func_ptr_vreg, arg_vregs, result_vregs)
}

///|
/// Lower call_ref instruction
/// call_ref calls through a function reference (tagged function pointer)
/// The func_ref is a tagged pointer (func_ptr | FUNCREF_TAG where FUNCREF_TAG = 0x2000000000000000)
/// The null check is already done in IR, so we just need to:
/// 1. Strip the FUNCREF_TAG to get the raw function pointer
/// 2. Call through the function pointer
fn lower_call_ref(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  _type_idx : Int,
) -> Unit {
  // First operand is the function reference (tagged function pointer)
  if inst.operands.length() == 0 {
    return
  }
  let func_ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Arguments are all operands except the first one
  let arg_vregs : Array[@abi.VReg] = []
  for i in 1..<inst.operands.length() {
    arg_vregs.push(ctx.get_vreg_for_use(inst.operands[i], block))
  }

  // Get all result vregs
  let result_vregs : Array[@abi.VReg] = []
  for result in inst.all_results() {
    result_vregs.push(ctx.get_vreg(result))
  }

  // Step 1: Strip FUNCREF_TAG (0x2000000000000000) to get raw function pointer
  // func_ptr = func_ref & 0x1FFFFFFFFFFFFFFF (clear bit 61)
  let mask_vreg = ctx.vcode_func.new_vreg(Int)
  let load_mask = @instr.VCodeInst::new(LoadConst(0x1FFFFFFFFFFFFFFFL))
  load_mask.add_def({ reg: Virtual(mask_vreg) })
  block.add_inst(load_mask)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let and_inst = @instr.VCodeInst::new(And)
  and_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  and_inst.add_use(Virtual(func_ref_vreg))
  and_inst.add_use(Virtual(mask_vreg))
  block.add_inst(and_inst)

  // Step 2: Use Cranelift-style call lowering
  lower_wasm_call(ctx, block, func_ptr_vreg, arg_vregs, result_vregs)
}

///|
/// Add clobber definitions for all caller-saved registers to a call instruction.
/// This tells the register allocator that these registers are destroyed by the call,
/// so any values that need to survive across the call must be spilled or allocated
/// to callee-saved registers.
fn add_call_clobbers(call_inst : @instr.VCodeInst) -> Unit {
  // Add clobbers for all caller-saved GPRs (X0-X17)
  for preg in @abi.call_clobbered_gprs() {
    call_inst.add_def({ reg: Physical(preg) })
  }
  // Add clobbers for all caller-saved FPRs (D0-D7)
  for preg in @abi.call_clobbered_fprs() {
    call_inst.add_def({ reg: Physical(preg) })
  }
}

///|
/// Lower global.get instruction
/// Loads a global variable value
///
/// Cranelift-style lowering: expand to LoadPtr instructions here
/// instead of deferring to emit phase with hardcoded registers.
///
/// Generated sequence:
/// 1. globals_ptr = LoadPtr(I64, VMCTX_GLOBALS_OFFSET) from vmctx (X19)
/// 2. result = LoadPtr(I64, global_idx * 16) from globals_ptr
fn lower_global_get(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  global_idx : Int,
) -> Unit {
  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Step 1: Load globals array pointer from vmctx
  // vmctx is pinned to X19, use it as Physical register
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }
  let globals_ptr = ctx.new_vreg(@abi.Int)
  let load_globals = @instr.VCodeInst::new(
    LoadPtr(@instr.I64, @abi.VMCTX_GLOBALS_OFFSET),
  )
  load_globals.add_use(Physical(vmctx_preg))
  load_globals.add_def({ reg: Virtual(globals_ptr) })
  block.add_inst(load_globals)

  // Step 2: Load global value from globals array
  // Each global is 16 bytes (value + type tag)
  let offset = global_idx * 16
  let mem_ty = ir_type_to_mem_type(result.ty)
  let load_value = @instr.VCodeInst::new(LoadPtr(mem_ty, offset))
  load_value.add_use(Virtual(globals_ptr))
  load_value.add_def({ reg: Virtual(result_vreg) })
  block.add_inst(load_value)
}

///|
/// Lower global.set instruction
/// Stores a value to a global variable
///
/// Cranelift-style lowering: expand to LoadPtr + StorePtr instructions
/// instead of deferring to emit phase with hardcoded registers.
///
/// Generated sequence:
/// 1. globals_ptr = LoadPtr(I64, VMCTX_GLOBALS_OFFSET) from vmctx (X19)
/// 2. StorePtr(I64, global_idx * 16) value to globals_ptr
fn lower_global_set(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  global_idx : Int,
) -> Unit {
  // Get the value operand
  guard inst.operands.length() > 0 else { return }
  let value = ctx.get_vreg_for_use(inst.operands[0], block)

  // Step 1: Load globals array pointer from vmctx
  // vmctx is pinned to X19, use it as Physical register
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }
  let globals_ptr = ctx.new_vreg(@abi.Int)
  let load_globals = @instr.VCodeInst::new(
    LoadPtr(@instr.I64, @abi.VMCTX_GLOBALS_OFFSET),
  )
  load_globals.add_use(Physical(vmctx_preg))
  load_globals.add_def({ reg: Virtual(globals_ptr) })
  block.add_inst(load_globals)

  // Step 2: Store global value to globals array
  // Each global is 16 bytes (value + type tag)
  let offset = global_idx * 16
  let mem_ty = ir_type_to_mem_type(inst.operands[0].ty)
  let store_value = @instr.VCodeInst::new(StorePtr(mem_ty, offset))
  store_value.add_use(Virtual(globals_ptr)) // base address
  store_value.add_use(Virtual(value)) // value to store
  block.add_inst(store_value)
}

// ============ Raw Pointer Operations (for trampolines) ============

///|
/// Lower load_ptr instruction (raw pointer load without bounds checking)
/// Used in trampolines to load arguments from values_vec
fn lower_load_ptr(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  ty : @ir.Type,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Get the base pointer and offset from operands
  // operand 0 = base pointer (values_vec)
  // operand 1 = offset constant (optional, if 2 operands)
  let base = ctx.get_vreg_for_use(inst.operands[0], block)

  // Check if we have an offset from a second operand (must be an iconst)
  let offset = if inst.operands.length() > 1 {
    // Try to extract constant offset
    if find_defining_inst(ctx, inst.operands[1]) is Some(def_inst) &&
      def_inst.opcode is @ir.Opcode::Iconst(off) {
      off.to_int()
    } else {
      // If not a constant, we'd need to add the offset separately
      // For simplicity in trampolines, we assume constant offsets
      0
    }
  } else {
    0
  }

  // Convert IR type to VCode memory type
  let mem_ty = ir_type_to_mem_type(ty)

  // Create LoadPtr instruction
  let load_inst = @instr.VCodeInst::new(LoadPtr(mem_ty, offset))
  load_inst.add_def({ reg: Virtual(result_vreg) })
  load_inst.add_use(Virtual(base))
  block.add_inst(load_inst)
}

///|
/// Lower store_ptr instruction (raw pointer store without bounds checking)
/// Used in trampolines to store results to values_vec
fn lower_store_ptr(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  ty : @ir.Type,
) -> Unit {
  // operand 0 = base pointer
  // operand 1 = value to store
  // operand 2 = offset constant (optional)
  guard inst.operands.length() >= 2 else { return }
  let base = ctx.get_vreg_for_use(inst.operands[0], block)
  let value = ctx.get_vreg_for_use(inst.operands[1], block)

  // Check if we have an offset from a third operand
  let offset = if inst.operands.length() > 2 {
    if find_defining_inst(ctx, inst.operands[2]) is Some(def_inst) &&
      def_inst.opcode is @ir.Opcode::Iconst(off) {
      off.to_int()
    } else {
      0
    }
  } else {
    0
  }

  // Convert IR type to VCode memory type
  let mem_ty = ir_type_to_mem_type(ty)

  // Create StorePtr instruction
  let store_inst = @instr.VCodeInst::new(StorePtr(mem_ty, offset))
  store_inst.add_use(Virtual(base))
  store_inst.add_use(Virtual(value))
  block.add_inst(store_inst)
}

///|
/// Lower call_ptr instruction (call through a function pointer)
/// Used in trampolines to call the target WASM function
///
/// Operand layout (following Cranelift):
///   operand 0 = function pointer
///   operand 1 = callee_vmctx (X0)
///   operand 2 = caller_vmctx (X1)
///   operands 3..n = user arguments
///
/// Cranelift-style ABI refactoring:
/// - Stack args are handled in lower phase via StoreToStack instructions
/// - Register args use FixedReg constraints to tell regalloc which physical registers to use
/// - X17 is used for func_ptr (constraint ensures no conflicts)
fn lower_call_ptr(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  num_args : Int,
  num_results : Int,
) -> Unit {
  // Collect function pointer
  let func_ptr = ctx.get_vreg_for_use(inst.operands[0], block)

  // Collect vmctx arguments
  let callee_vmctx = ctx.get_vreg_for_use(inst.operands[1], block)
  let caller_vmctx = ctx.get_vreg_for_use(inst.operands[2], block)

  // Classify user arguments by type (starting from operand index 3)
  // int_args and float_args contain (vreg, class) tuples
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for i in 3..<inst.operands.length() {
    let vreg = ctx.get_vreg_for_use(inst.operands[i], block)
    match vreg.class {
      @abi.Int => int_args.push((vreg, @abi.Int))
      @abi.Float32 => float_args.push((vreg, @abi.Float32))
      @abi.Float64 => float_args.push((vreg, @abi.Float64))
    }
  }

  // Calculate overflow args count
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS // 6 (X2-X7)
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS // 8 (V0-V7)
  let int_overflow = if int_args.length() > max_int_reg_args {
    int_args.length() - max_int_reg_args
  } else {
    0
  }
  let float_overflow = if float_args.length() > max_float_reg_args {
    float_args.length() - max_float_reg_args
  } else {
    0
  }
  let stack_arg_space = (int_overflow + float_overflow) * 8
  // Align to 16 bytes
  let aligned_stack_space = (stack_arg_space + 15) / 16 * 16

  // Update max_outgoing_args_size (Cranelift-style: pre-allocate in prologue)
  // This ensures SP doesn't move during call sequences, avoiding spill slot issues
  ctx.vcode_func.update_max_outgoing_args_size(aligned_stack_space)

  // Step 1: Store overflow int args to stack (space is pre-allocated in prologue)
  for i in max_int_reg_args..<int_args.length() {
    let (vreg, _) = int_args[i]
    let stack_idx = i - max_int_reg_args
    let offset = stack_idx * 8
    let store = @instr.VCodeInst::new(StoreToStack(offset))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }

  // Step 2: Store overflow float args to stack (after int overflow args)
  for i in max_float_reg_args..<float_args.length() {
    let (vreg, _) = float_args[i]
    let stack_idx = i - max_float_reg_args
    let offset = int_overflow * 8 + stack_idx * 8
    let store = @instr.VCodeInst::new(StoreToStack(offset))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }

  // Step 3: Create CallPtr instruction with FixedReg constraints (Wasm calling convention)
  let call_inst = @instr.VCodeInst::new(CallPtr(num_args, num_results, Wasm))

  // func_ptr constrained to X17
  call_inst.add_use_fixed(Virtual(func_ptr), @abi.PReg::{
    index: 17,
    class: @abi.Int,
  })

  // callee_vmctx constrained to X0
  call_inst.add_use_fixed(Virtual(callee_vmctx), @abi.PReg::{
    index: 0,
    class: @abi.Int,
  })

  // caller_vmctx constrained to X1
  call_inst.add_use_fixed(Virtual(caller_vmctx), @abi.PReg::{
    index: 1,
    class: @abi.Int,
  })

  // Register int args: X2-X7
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg_idx = 2 + i // X2, X3, X4, X5, X6, X7
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{
      index: preg_idx,
      class: @abi.Int,
    })
  }

  // Register float args: V0-V7
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, class) = float_args[i]
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{ index: i, class })
  }

  // Step 4: Define results with constraints
  let all_results = inst.all_results()
  let mut int_result_idx = 0
  let mut float_result_idx = 0
  for result in all_results {
    let dst = ctx.get_vreg(result)
    match dst.class {
      @abi.Int => {
        // Integer results go to X0, X1, ...
        call_inst.add_def_fixed({ reg: Virtual(dst) }, @abi.PReg::{
          index: int_result_idx,
          class: @abi.Int,
        })
        int_result_idx = int_result_idx + 1
      }
      @abi.Float32 | @abi.Float64 => {
        // Float results go to V0, V1, ...
        call_inst.add_def_fixed({ reg: Virtual(dst) }, @abi.PReg::{
          index: float_result_idx,
          class: dst.class,
        })
        float_result_idx = float_result_idx + 1
      }
    }
  }

  // Add clobbers for all caller-saved registers
  add_call_clobbers(call_inst)
  block.add_inst(call_inst)
  // No AdjustSP needed - outgoing args space is pre-allocated in prologue
}

// ============ C Libcall Lowering (Cranelift-style) ============

///|
/// Lower a simple C libcall with up to 8 integer arguments.
/// This is for calling C runtime functions like GC helpers.
/// Uses standard C calling convention: args go to X0-X7, result in X0.
///
/// Unlike lower_call_ptr which handles Wasm calling convention with vmctx,
/// this is for simple C functions where args go directly to X0-X7.
fn lower_c_libcall(
  _ctx : LoweringContext,
  block : @block.VCodeBlock,
  func_ptr : @abi.VReg,
  args : Array[@abi.VReg],
  result : @abi.VReg?,
) -> Unit {
  guard args.length() <= 8 else {
    abort("lower_c_libcall: too many arguments (max 8)")
  }

  // Create CallPtr instruction with C calling convention
  let num_args = args.length()
  let num_results = if result is Some(_) { 1 } else { 0 }
  let call_inst = @instr.VCodeInst::new(CallPtr(num_args, num_results, C))

  // func_ptr constrained to X17
  call_inst.add_use_fixed(Virtual(func_ptr), @abi.PReg::{
    index: 17,
    class: @abi.Int,
  })

  // Args constrained to X0, X1, X2, ... (C calling convention)
  for i, arg in args {
    call_inst.add_use_fixed(Virtual(arg), @abi.PReg::{
      index: i,
      class: @abi.Int,
    })
  }

  // Result constrained to X0
  if result is Some(dst) {
    call_inst.add_def_fixed({ reg: Virtual(dst) }, @abi.PReg::{
      index: 0,
      class: @abi.Int,
    })
  }

  // Add clobbers for all caller-saved registers
  add_call_clobbers(call_inst)
  block.add_inst(call_inst)
}

///|
/// Helper to materialize an immediate value into a vreg
fn materialize_imm(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  value : Int64,
) -> @abi.VReg {
  let vreg = ctx.vcode_func.new_vreg(Int)
  let mov = @instr.VCodeInst::new(LoadConst(value))
  mov.add_def({ reg: Virtual(vreg) })
  block.add_inst(mov)
  vreg
}

// ============ Wasm Call Lowering (Cranelift-style) ============

///|
/// Lower a Wasm function call using Cranelift-style approach.
/// All argument placement is done in lowering via FixedReg constraints.
/// The emit phase just emits BLR X17.
///
/// Wasm v3 ABI:
/// - X0 = callee_vmctx, X1 = caller_vmctx
/// - X2-X7 = integer user args (up to 6)
/// - V0-V7 = float user args (up to 8)
/// - Overflow args go to stack
/// - X0/V0 = first result, etc.
fn lower_wasm_call(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  func_ptr : @abi.VReg,
  args : Array[@abi.VReg],
  results : Array[@abi.VReg],
) -> Unit {
  // vmctx is always in X19
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }

  // Classify user arguments by type
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for arg in args {
    match arg.class {
      @abi.Int => int_args.push((arg, @abi.Int))
      @abi.Float32 => float_args.push((arg, @abi.Float32))
      @abi.Float64 => float_args.push((arg, @abi.Float64))
    }
  }

  // Calculate overflow args
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS // 6 (X2-X7)
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS // 8 (V0-V7)
  let int_overflow = if int_args.length() > max_int_reg_args {
    int_args.length() - max_int_reg_args
  } else {
    0
  }
  let float_overflow = if float_args.length() > max_float_reg_args {
    float_args.length() - max_float_reg_args
  } else {
    0
  }
  let total_overflow = int_overflow + float_overflow

  // Generate StoreToStack for overflow arguments
  // These use the pre-allocated outgoing args area (offset from SP)
  for i in max_int_reg_args..<int_args.length() {
    let (vreg, _) = int_args[i]
    let stack_idx = i - max_int_reg_args
    let offset = stack_idx * 8
    let store = @instr.VCodeInst::new(StoreToStack(offset))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }
  for i in max_float_reg_args..<float_args.length() {
    let (vreg, _) = float_args[i]
    let stack_idx = i - max_float_reg_args
    let offset = int_overflow * 8 + stack_idx * 8
    let store = @instr.VCodeInst::new(StoreToStack(offset))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }

  // Track outgoing args size for frame layout
  if total_overflow > 0 {
    let overflow_bytes = total_overflow * 8
    ctx.vcode_func.update_max_outgoing_args_size(overflow_bytes)
  }

  // Create CallPtr instruction with Wasm calling convention
  let num_args = args.length()
  let num_results = results.length()
  let call_inst = @instr.VCodeInst::new(CallPtr(num_args, num_results, Wasm))

  // func_ptr constrained to X17
  call_inst.add_use_fixed(Virtual(func_ptr), @abi.PReg::{
    index: 17,
    class: @abi.Int,
  })

  // vmctx constrained to X0 (callee_vmctx) and X1 (caller_vmctx)
  // Note: We need to copy vmctx (X19) into vregs so regalloc will insert moves
  // Using Physical directly doesn't trigger move insertion
  let callee_vmctx = ctx.vcode_func.new_vreg(Int)
  let caller_vmctx = ctx.vcode_func.new_vreg(Int)
  let copy_callee = @instr.VCodeInst::new(Move)
  copy_callee.add_def({ reg: Virtual(callee_vmctx) })
  copy_callee.add_use(Physical(vmctx_preg))
  block.add_inst(copy_callee)
  let copy_caller = @instr.VCodeInst::new(Move)
  copy_caller.add_def({ reg: Virtual(caller_vmctx) })
  copy_caller.add_use(Physical(vmctx_preg))
  block.add_inst(copy_caller)
  call_inst.add_use_fixed(Virtual(callee_vmctx), @abi.PReg::{
    index: 0,
    class: @abi.Int,
  })
  call_inst.add_use_fixed(Virtual(caller_vmctx), @abi.PReg::{
    index: 1,
    class: @abi.Int,
  })

  // Register int args: X2-X7
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg_idx = 2 + i // X2, X3, X4, X5, X6, X7
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{
      index: preg_idx,
      class: @abi.Int,
    })
  }

  // Register float args: V0-V7
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, class) = float_args[i]
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{ index: i, class })
  }

  // Define results with fixed register constraints
  // Classify results by type and assign to X0-X7 / V0-V7
  let mut int_result_idx = 0
  let mut float_result_idx = 0
  for result in results {
    match result.class {
      @abi.Int => {
        call_inst.add_def_fixed({ reg: Virtual(result) }, @abi.PReg::{
          index: int_result_idx,
          class: @abi.Int,
        })
        int_result_idx += 1
      }
      @abi.Float32 => {
        call_inst.add_def_fixed({ reg: Virtual(result) }, @abi.PReg::{
          index: float_result_idx,
          class: @abi.Float32,
        })
        float_result_idx += 1
      }
      @abi.Float64 => {
        call_inst.add_def_fixed({ reg: Virtual(result) }, @abi.PReg::{
          index: float_result_idx,
          class: @abi.Float64,
        })
        float_result_idx += 1
      }
    }
  }

  // Add clobbers for all caller-saved registers
  add_call_clobbers(call_inst)
  block.add_inst(call_inst)
}

// ============ Tail Call Lowering (Cranelift-style) ============

///|
/// Lower direct return_call (tail call optimization)
/// Following Cranelift: parameters are handled in lowering phase
/// - Overflow args: StoreToStack instructions
/// - Register args: Fixed register constraints via add_use_fixed
/// - ReturnCallIndirect instruction only contains func_ptr use
fn lower_return_call(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  func_idx : Int,
) -> Unit {
  // Load func_table and get function pointer
  let func_table = emit_load_func_table(ctx, block)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let offset = func_idx * 8
  let load_inst = @instr.VCodeInst::new(Load(I64, offset))
  load_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  load_inst.add_use(Virtual(func_table))
  block.add_inst(load_inst)

  // Get vmctx (X19 is always vmctx)
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }

  // Classify user arguments by type
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for operand in inst.operands {
    let vreg = ctx.get_vreg_for_use(operand, block)
    match vreg.class {
      @abi.Int => int_args.push((vreg, @abi.Int))
      @abi.Float32 => float_args.push((vreg, @abi.Float32))
      @abi.Float64 => float_args.push((vreg, @abi.Float64))
    }
  }

  // Calculate overflow args count (user args, not including vmctx)
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS // 6 (X2-X7)
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS // 8 (V0-V7)
  let int_overflow = if int_args.length() > max_int_reg_args {
    int_args.length() - max_int_reg_args
  } else {
    0
  }

  // Generate StoreToStack instructions for overflow arguments
  for i in max_int_reg_args..<int_args.length() {
    let (vreg, _) = int_args[i]
    let stack_idx = i - max_int_reg_args
    let offset = stack_idx * 8
    let store = @instr.VCodeInst::new(StoreToStack(offset))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }
  for i in max_float_reg_args..<float_args.length() {
    let (vreg, _) = float_args[i]
    let stack_idx = i - max_float_reg_args
    let offset = int_overflow * 8 + stack_idx * 8
    let store = @instr.VCodeInst::new(StoreToStack(offset))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }

  // Create ReturnCallIndirect instruction with fixed register constraints
  let call_inst = @instr.VCodeInst::new(ReturnCallIndirect(0, 0))

  // func_ptr constrained to X17
  call_inst.add_use_fixed(Virtual(func_ptr_vreg), @abi.PReg::{
    index: 17,
    class: @abi.Int,
  })

  // vmctx constrained to X0 and X1 (callee_vmctx = caller_vmctx = X19)
  call_inst.add_use_fixed(Physical(vmctx_preg), @abi.PReg::{
    index: 0,
    class: @abi.Int,
  })
  call_inst.add_use_fixed(Physical(vmctx_preg), @abi.PReg::{
    index: 1,
    class: @abi.Int,
  })

  // Register int args: X2-X7
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg_idx = 2 + i // X2, X3, X4, X5, X6, X7
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{
      index: preg_idx,
      class: @abi.Int,
    })
  }

  // Register float args: V0-V7
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, class) = float_args[i]
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{ index: i, class })
  }

  // No result defs for tail call (doesn't return to this function)
  // Add clobbers for caller-saved registers
  add_call_clobbers(call_inst)
  block.add_inst(call_inst)
}

///|
/// Lower return_call_indirect (indirect tail call)
/// Following Cranelift: parameters handled in lowering via StoreToStack and add_use_fixed
fn lower_return_call_indirect(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
  table_idx : Int,
) -> Unit {
  // Get element index and load function pointer (similar to lower_call_indirect)
  guard inst.operands.length() > 0 else { return }
  let elem_idx_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Load table pointer
  let table_ptr_vreg : @abi.VReg = if table_idx == 0 {
    emit_load_table0_base(ctx, block)
  } else {
    let indirect_tables_vreg = ctx.vcode_func.new_vreg(Int)
    let load_array_inst = @instr.VCodeInst::new(
      Load(I64, @abi.VMCTX_TABLES_OFFSET),
    )
    load_array_inst.add_def({ reg: Virtual(indirect_tables_vreg) })
    load_array_inst.add_use(Physical({ index: 19, class: Int }))
    block.add_inst(load_array_inst)
    let table_offset = table_idx * 8
    let ptr_vreg = ctx.vcode_func.new_vreg(Int)
    let load_table_inst = @instr.VCodeInst::new(Load(I64, table_offset))
    load_table_inst.add_def({ reg: Virtual(ptr_vreg) })
    load_table_inst.add_use(Virtual(indirect_tables_vreg))
    block.add_inst(load_table_inst)
    ptr_vreg
  }

  // Calculate offset and load function pointer
  let offset_vreg = ctx.vcode_func.new_vreg(Int)
  let const_16_vreg = ctx.vcode_func.new_vreg(Int)
  let load_16 = @instr.VCodeInst::new(LoadConst(16L))
  load_16.add_def({ reg: Virtual(const_16_vreg) })
  block.add_inst(load_16)
  let mul_inst = @instr.VCodeInst::new(Mul(true))
  mul_inst.add_def({ reg: Virtual(offset_vreg) })
  mul_inst.add_use(Virtual(elem_idx_vreg))
  mul_inst.add_use(Virtual(const_16_vreg))
  block.add_inst(mul_inst)
  let addr_vreg = ctx.vcode_func.new_vreg(Int)
  let add_inst = @instr.VCodeInst::new(Add(true))
  add_inst.add_def({ reg: Virtual(addr_vreg) })
  add_inst.add_use(Virtual(table_ptr_vreg))
  add_inst.add_use(Virtual(offset_vreg))
  block.add_inst(add_inst)
  // Load raw function pointer
  let raw_func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_func_inst = @instr.VCodeInst::new(Load(I64, 0))
  load_func_inst.add_def({ reg: Virtual(raw_func_ptr_vreg) })
  load_func_inst.add_use(Virtual(addr_vreg))
  block.add_inst(load_func_inst)

  // Clear FUNCREF_TAG (bit 61) from function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let mask_vreg = ctx.vcode_func.new_vreg(Int)
  let load_mask = @instr.VCodeInst::new(LoadConst(0xDFFFFFFFFFFFFFFFL))
  load_mask.add_def({ reg: Virtual(mask_vreg) })
  block.add_inst(load_mask)
  let and_inst = @instr.VCodeInst::new(And)
  and_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  and_inst.add_use(Virtual(raw_func_ptr_vreg))
  and_inst.add_use(Virtual(mask_vreg))
  block.add_inst(and_inst)
  let actual_type_vreg = ctx.vcode_func.new_vreg(Int)
  let load_type_inst = @instr.VCodeInst::new(Load(I64, 8))
  load_type_inst.add_def({ reg: Virtual(actual_type_vreg) })
  load_type_inst.add_use(Virtual(addr_vreg))
  block.add_inst(load_type_inst)
  let type_check_inst = @instr.VCodeInst::new(TypeCheckIndirect(type_idx))
  type_check_inst.add_use(Virtual(actual_type_vreg))
  block.add_inst(type_check_inst)

  // Get vmctx
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }

  // Classify user arguments (skip first operand which is elem_idx)
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for i in 1..<inst.operands.length() {
    let vreg = ctx.get_vreg_for_use(inst.operands[i], block)
    match vreg.class {
      @abi.Int => int_args.push((vreg, @abi.Int))
      @abi.Float32 => float_args.push((vreg, @abi.Float32))
      @abi.Float64 => float_args.push((vreg, @abi.Float64))
    }
  }

  // Calculate overflow
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS
  let int_overflow = if int_args.length() > max_int_reg_args {
    int_args.length() - max_int_reg_args
  } else {
    0
  }

  // Generate StoreToStack for overflow arguments
  for i in max_int_reg_args..<int_args.length() {
    let (vreg, _) = int_args[i]
    let stack_idx = i - max_int_reg_args
    let offset = stack_idx * 8
    let store = @instr.VCodeInst::new(StoreToStack(offset))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }
  for i in max_float_reg_args..<float_args.length() {
    let (vreg, _) = float_args[i]
    let stack_idx = i - max_float_reg_args
    let offset = int_overflow * 8 + stack_idx * 8
    let store = @instr.VCodeInst::new(StoreToStack(offset))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }

  // Create ReturnCallIndirect with fixed constraints
  let call_inst = @instr.VCodeInst::new(ReturnCallIndirect(0, 0))

  // func_ptr -> X17
  call_inst.add_use_fixed(Virtual(func_ptr_vreg), @abi.PReg::{
    index: 17,
    class: @abi.Int,
  })

  // vmctx -> X0, X1
  call_inst.add_use_fixed(Physical(vmctx_preg), @abi.PReg::{
    index: 0,
    class: @abi.Int,
  })
  call_inst.add_use_fixed(Physical(vmctx_preg), @abi.PReg::{
    index: 1,
    class: @abi.Int,
  })

  // Register int args: X2-X7
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg_idx = 2 + i
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{
      index: preg_idx,
      class: @abi.Int,
    })
  }

  // Register float args: V0-V7
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, class) = float_args[i]
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{ index: i, class })
  }
  add_call_clobbers(call_inst)
  block.add_inst(call_inst)
}

///|
/// Lower return_call_ref (tail call through function reference)
/// The func_ref is a tagged pointer (func_ptr | FUNCREF_TAG where FUNCREF_TAG = 0x2000000000000000)
/// Following Cranelift: parameters handled in lowering
fn lower_return_call_ref(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  _type_idx : Int,
) -> Unit {
  guard inst.operands.length() > 0 else { return }
  let func_ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Strip FUNCREF_TAG (0x2000000000000000) to get raw function pointer
  // func_ptr = func_ref & 0x1FFFFFFFFFFFFFFF (clear bit 61)
  let mask_vreg = ctx.vcode_func.new_vreg(Int)
  let load_mask = @instr.VCodeInst::new(LoadConst(0x1FFFFFFFFFFFFFFFL))
  load_mask.add_def({ reg: Virtual(mask_vreg) })
  block.add_inst(load_mask)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let and_inst = @instr.VCodeInst::new(And)
  and_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  and_inst.add_use(Virtual(func_ref_vreg))
  and_inst.add_use(Virtual(mask_vreg))
  block.add_inst(and_inst)

  // Get vmctx
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }

  // Classify user arguments (skip first operand which is func_ref)
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for i in 1..<inst.operands.length() {
    let vreg = ctx.get_vreg_for_use(inst.operands[i], block)
    match vreg.class {
      @abi.Int => int_args.push((vreg, @abi.Int))
      @abi.Float32 => float_args.push((vreg, @abi.Float32))
      @abi.Float64 => float_args.push((vreg, @abi.Float64))
    }
  }

  // Calculate overflow
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS
  let int_overflow = if int_args.length() > max_int_reg_args {
    int_args.length() - max_int_reg_args
  } else {
    0
  }

  // Generate StoreToStack for overflow arguments
  for i in max_int_reg_args..<int_args.length() {
    let (vreg, _) = int_args[i]
    let stack_idx = i - max_int_reg_args
    let offset = stack_idx * 8
    let store = @instr.VCodeInst::new(StoreToStack(offset))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }
  for i in max_float_reg_args..<float_args.length() {
    let (vreg, _) = float_args[i]
    let stack_idx = i - max_float_reg_args
    let offset = int_overflow * 8 + stack_idx * 8
    let store = @instr.VCodeInst::new(StoreToStack(offset))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }

  // Create ReturnCallIndirect with fixed constraints
  let call_inst = @instr.VCodeInst::new(ReturnCallIndirect(0, 0))

  // func_ptr -> X17
  call_inst.add_use_fixed(Virtual(func_ptr_vreg), @abi.PReg::{
    index: 17,
    class: @abi.Int,
  })

  // vmctx -> X0, X1
  call_inst.add_use_fixed(Physical(vmctx_preg), @abi.PReg::{
    index: 0,
    class: @abi.Int,
  })
  call_inst.add_use_fixed(Physical(vmctx_preg), @abi.PReg::{
    index: 1,
    class: @abi.Int,
  })

  // Register int args: X2-X7
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg_idx = 2 + i
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{
      index: preg_idx,
      class: @abi.Int,
    })
  }

  // Register float args: V0-V7
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, class) = float_args[i]
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{ index: i, class })
  }
  add_call_clobbers(call_inst)
  block.add_inst(call_inst)
}

// ============ GC Operations ============

///|
/// Lower i31.new: Convert i32 to i31ref
/// Encoding: (value << 1) | 1 (positive odd for i31)
fn lower_i31_new(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)

  // Step 1: Zero-extend i32 to i64
  let ext_vreg = ctx.vcode_func.new_vreg(Int)
  let extend_inst = @instr.VCodeInst::new(Extend(Unsigned32To64))
  extend_inst.add_def({ reg: Virtual(ext_vreg) })
  extend_inst.add_use(Virtual(src))
  block.add_inst(extend_inst)

  // Step 2: Shift left by 1
  let shifted_vreg = ctx.vcode_func.new_vreg(Int)
  let one_vreg = ctx.vcode_func.new_vreg(Int)
  let load_one = @instr.VCodeInst::new(LoadConst(1L))
  load_one.add_def({ reg: Virtual(one_vreg) })
  block.add_inst(load_one)
  let shift_inst = @instr.VCodeInst::new(Shl(true))
  shift_inst.add_def({ reg: Virtual(shifted_vreg) })
  shift_inst.add_use(Virtual(ext_vreg))
  shift_inst.add_use(Virtual(one_vreg))
  block.add_inst(shift_inst)

  // Step 3: OR with 1 to set low bit
  let or_inst = @instr.VCodeInst::new(Or)
  or_inst.add_def({ reg: Virtual(dst) })
  or_inst.add_use(Virtual(shifted_vreg))
  or_inst.add_use(Virtual(one_vreg))
  block.add_inst(or_inst)
}

///|
/// Lower i31.get_s: Sign-extend 31 bits to i32
/// Encoding is (value << 1) | 1, so:
/// 1. Check for null (0) and trap
/// 2. Shift right by 1 to decode (removes the tag bit)
/// 3. Sign-extend from 31 bits
fn lower_i31_get_s(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)

  // Step 0: Null check - trap if i31 ref is null (0)
  let trap_inst = @instr.VCodeInst::new(TrapIfZero(true, 2))
  trap_inst.add_use(Virtual(src))
  block.add_inst(trap_inst)

  // Step 1: Shift right by 1 to decode the i31 value (64-bit)
  let shift_amount = ctx.new_vreg(@abi.Int)
  let load_1 = @instr.VCodeInst::new(LoadConst(1L))
  load_1.add_def({ reg: Virtual(shift_amount) })
  block.add_inst(load_1)
  let decoded = ctx.new_vreg(@abi.Int)
  let lsr_inst = @instr.VCodeInst::new(LShr(true))
  lsr_inst.add_def({ reg: Virtual(decoded) })
  lsr_inst.add_use(Virtual(src))
  lsr_inst.add_use(Virtual(shift_amount))
  block.add_inst(lsr_inst)

  // Step 2: Truncate to 32 bits
  let tmp = ctx.new_vreg(@abi.Int)
  let trunc_inst = @instr.VCodeInst::new(Truncate)
  trunc_inst.add_def({ reg: Virtual(tmp) })
  trunc_inst.add_use(Virtual(decoded))
  block.add_inst(trunc_inst)

  // Step 3: Sign-extend from 31 bits by shifting left then arithmetic right
  let tmp2 = ctx.new_vreg(@abi.Int)
  let shl_inst = @instr.VCodeInst::new(Shl(false))
  shl_inst.add_def({ reg: Virtual(tmp2) })
  shl_inst.add_use(Virtual(tmp))
  shl_inst.add_use(Virtual(shift_amount))
  block.add_inst(shl_inst)
  let asr_inst = @instr.VCodeInst::new(AShr(false))
  asr_inst.add_def({ reg: Virtual(dst) })
  asr_inst.add_use(Virtual(tmp2))
  asr_inst.add_use(Virtual(shift_amount))
  block.add_inst(asr_inst)
}

///|
/// Lower i31.get_u: Zero-extend 31 bits
/// Encoding is (value << 1) | 1, so:
/// 1. Check for null (0) and trap
/// 2. Shift right by 1 to decode (removes the tag bit)
/// 3. Mask with 0x7FFFFFFF for 31 bits
fn lower_i31_get_u(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)

  // Step 0: Null check - trap if i31 ref is null (0)
  let trap_inst = @instr.VCodeInst::new(TrapIfZero(true, 2))
  trap_inst.add_use(Virtual(src))
  block.add_inst(trap_inst)

  // Step 1: Shift right by 1 to decode the i31 value (64-bit)
  let shift_amount = ctx.new_vreg(@abi.Int)
  let load_1 = @instr.VCodeInst::new(LoadConst(1L))
  load_1.add_def({ reg: Virtual(shift_amount) })
  block.add_inst(load_1)
  let decoded = ctx.new_vreg(@abi.Int)
  let lsr_inst = @instr.VCodeInst::new(LShr(true))
  lsr_inst.add_def({ reg: Virtual(decoded) })
  lsr_inst.add_use(Virtual(src))
  lsr_inst.add_use(Virtual(shift_amount))
  block.add_inst(lsr_inst)

  // Step 2: Truncate to 32 bits
  let tmp = ctx.new_vreg(@abi.Int)
  let trunc_inst = @instr.VCodeInst::new(Truncate)
  trunc_inst.add_def({ reg: Virtual(tmp) })
  trunc_inst.add_use(Virtual(decoded))
  block.add_inst(trunc_inst)

  // Step 3: Mask with 0x7FFFFFFF for 31 bits (already decoded, just ensure upper bit is clear)
  let mask = ctx.new_vreg(@abi.Int)
  let load_mask = @instr.VCodeInst::new(LoadConst(0x7FFFFFFFL))
  load_mask.add_def({ reg: Virtual(mask) })
  block.add_inst(load_mask)
  let and_inst = @instr.VCodeInst::new(And)
  and_inst.add_def({ reg: Virtual(dst) })
  and_inst.add_use(Virtual(tmp))
  and_inst.add_use(Virtual(mask))
  block.add_inst(and_inst)
}

///|
/// Lower GC type conversions (any.convert_extern, extern.convert_any)
/// These are no-ops in the JIT - just pass the reference through
fn lower_gc_convert(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  // Just move the value - the representation is the same
  let vcode_inst = @instr.VCodeInst::new(Move)
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(src))
  block.add_inst(vcode_inst)
}

///|
/// Lower ref.test: Test if reference matches type
/// Uses runtime libcall: gc_ref_test_impl(ref, type_idx, nullable) -> 0 or 1
fn lower_ref_test(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
  nullable : Bool,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Materialize immediate arguments
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  let nullable_vreg = materialize_imm(
    ctx,
    block,
    if nullable {
      1L
    } else {
      0L
    },
  )
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(RefTest))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_ref_test_impl(ref, type_idx, nullable) -> result
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, nullable_vreg],
    Some(dst),
  )
}

///|
/// Lower ref.cast: Cast reference to type (traps on failure)
/// Uses runtime libcall: gc_ref_cast_impl(ref, type_idx, nullable) -> ref or trap
fn lower_ref_cast(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
  nullable : Bool,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Materialize immediate arguments
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  let nullable_vreg = materialize_imm(
    ctx,
    block,
    if nullable {
      1L
    } else {
      0L
    },
  )
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(RefCast))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_ref_cast_impl(ref, type_idx, nullable) -> result
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, nullable_vreg],
    Some(dst),
  )
}

///|
/// Lower ref.eq: Compare two references for equality
/// Returns 1 if equal, 0 otherwise
fn lower_ref_eq(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let ref1_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let ref2_vreg = ctx.get_vreg_for_use(inst.operands[1], block)

  // Compare two references as i64 values
  // Use Cmp(Eq, true) for 64-bit equality comparison
  let cmp_inst = @instr.VCodeInst::new(Cmp(@instr.CmpKind::Eq, true))
  cmp_inst.add_def({ reg: Virtual(dst) })
  cmp_inst.add_use(Virtual(ref1_vreg))
  cmp_inst.add_use(Virtual(ref2_vreg))
  block.add_inst(cmp_inst)
}

///|
/// Lower struct.new: Allocate struct with field values
/// Uses runtime libcall: gc_struct_new_impl(type_idx, fields_ptr, num_fields) -> struct_ref
fn lower_struct_new(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let num_fields = inst.operands.length()

  // Materialize arguments
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  let num_fields_vreg = materialize_imm(ctx, block, num_fields.to_int64())

  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(StructNew))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  if num_fields > 0 {
    // Allocate stack space for fields (8 bytes each, aligned to 16)
    let stack_space = (num_fields * 8 + 15) / 16 * 16
    let alloc = @instr.VCodeInst::new(AdjustSP(-stack_space))
    block.add_inst(alloc)

    // Store each field value to stack
    for i in 0..<num_fields {
      let field_vreg = ctx.get_vreg_for_use(inst.operands[i], block)
      let offset = i * 8
      let store = @instr.VCodeInst::new(StoreToStack(offset))
      store.add_use(Virtual(field_vreg))
      block.add_inst(store)
    }

    // Get current stack pointer as fields_ptr
    let sp_vreg = ctx.vcode_func.new_vreg(Int)
    let load_sp = @instr.VCodeInst::new(LoadSP)
    load_sp.add_def({ reg: Virtual(sp_vreg) })
    block.add_inst(load_sp)

    // Call: gc_struct_new_impl(type_idx, fields_ptr, num_fields) -> result
    lower_c_libcall(
      ctx,
      block,
      func_ptr_vreg,
      [type_idx_vreg, sp_vreg, num_fields_vreg],
      Some(dst),
    )

    // Deallocate stack space
    let dealloc = @instr.VCodeInst::new(AdjustSP(stack_space))
    block.add_inst(dealloc)
  } else {
    // No fields - pass null pointer
    let null_ptr = materialize_imm(ctx, block, 0L)
    // Call: gc_struct_new_impl(type_idx, null, 0) -> result
    lower_c_libcall(
      ctx,
      block,
      func_ptr_vreg,
      [type_idx_vreg, null_ptr, num_fields_vreg],
      Some(dst),
    )
  }
}

///|
/// Lower struct.new_default: Allocate struct with default values
/// Uses runtime libcall: gc_struct_new_impl(type_idx, null, 0) -> struct_ref
fn lower_struct_new_default(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)

  // Materialize arguments
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  let zero_vreg = materialize_imm(ctx, block, 0L)

  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(StructNew))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // Call: gc_struct_new_impl(type_idx, null, 0) -> result
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [type_idx_vreg, zero_vreg, zero_vreg],
    Some(dst),
  )
}

///|
/// Lower struct.get: Get struct field value
/// Uses runtime libcall: gc_struct_get_impl(ref, type_idx, field_idx) -> value
fn lower_struct_get(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
  field_idx : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Materialize immediate arguments
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  let field_idx_vreg = materialize_imm(ctx, block, field_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(StructGet))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Check if result is a float type - C libcall returns int64, need bitcast
  let is_float = result.ty is (@ir.Type::F32 | @ir.Type::F64)
  if is_float {
    // For float results: call returns int64, then bitcast to float
    let int_result = ctx.vcode_func.new_vreg(Int)
    lower_c_libcall(
      ctx,
      block,
      func_ptr_vreg,
      [ref_vreg, type_idx_vreg, field_idx_vreg],
      Some(int_result),
    )
    // Bitcast from int to float
    let bitcast = @instr.VCodeInst::new(Bitcast)
    bitcast.add_def({ reg: Virtual(dst) })
    bitcast.add_use(Virtual(int_result))
    block.add_inst(bitcast)
  } else {
    // For integer results: call returns directly
    lower_c_libcall(
      ctx,
      block,
      func_ptr_vreg,
      [ref_vreg, type_idx_vreg, field_idx_vreg],
      Some(dst),
    )
  }
}

///|
/// Lower struct.get_s: Get struct field value with sign extension
/// Uses runtime libcall then sign extends based on byte_width
fn lower_struct_get_s(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
  field_idx : Int,
  byte_width : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Materialize immediate arguments
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  let field_idx_vreg = materialize_imm(ctx, block, field_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(StructGet))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call and get raw value
  let raw_result = ctx.vcode_func.new_vreg(Int)
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, field_idx_vreg],
    Some(raw_result),
  )
  // Sign extend based on byte_width
  // For i8 (byte_width=1): sign extend byte to i32
  // For i16 (byte_width=2): sign extend halfword to i32
  if byte_width == 1 {
    // SXTB: Sign extend byte to 32-bit
    let ext = @instr.VCodeInst::new(Extend(Signed8To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else if byte_width == 2 {
    // SXTH: Sign extend halfword to 32-bit
    let ext = @instr.VCodeInst::new(Extend(Signed16To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else {
    // No extension needed, just move
    let mov = @instr.VCodeInst::new(Move)
    mov.add_def({ reg: Virtual(dst) })
    mov.add_use(Virtual(raw_result))
    block.add_inst(mov)
  }
}

///|
/// Lower struct.get_u: Get struct field value with zero extension
/// Uses runtime libcall then zero extends based on byte_width
fn lower_struct_get_u(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
  field_idx : Int,
  byte_width : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Materialize immediate arguments
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  let field_idx_vreg = materialize_imm(ctx, block, field_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(StructGet))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call and get raw value
  let raw_result = ctx.vcode_func.new_vreg(Int)
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, field_idx_vreg],
    Some(raw_result),
  )
  // Zero extend based on byte_width
  // For i8 (byte_width=1): mask with 0xFF
  // For i16 (byte_width=2): mask with 0xFFFF
  if byte_width == 1 {
    // UXTB: Zero extend byte to 32-bit
    let ext = @instr.VCodeInst::new(Extend(Unsigned8To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else if byte_width == 2 {
    // UXTH: Zero extend halfword to 32-bit
    let ext = @instr.VCodeInst::new(Extend(Unsigned16To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else {
    // No extension needed, just move
    let mov = @instr.VCodeInst::new(Move)
    mov.add_def({ reg: Virtual(dst) })
    mov.add_use(Virtual(raw_result))
    block.add_inst(mov)
  }
}

///|
/// Lower struct.set: Set struct field value
/// Uses runtime libcall: gc_struct_set_impl(ref, type_idx, field_idx, value)
fn lower_struct_set(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
  field_idx : Int,
) -> Unit {
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let val_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  // Materialize immediate arguments
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  let field_idx_vreg = materialize_imm(ctx, block, field_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(StructSet))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Check if value is a float type - C libcall expects int64, need bitcast
  let is_float = inst.operands[1].ty is (@ir.Type::F32 | @ir.Type::F64)
  let actual_val_vreg = if is_float {
    // For float values: bitcast to int before passing to C function
    let int_val = ctx.vcode_func.new_vreg(Int)
    let bitcast = @instr.VCodeInst::new(Bitcast)
    bitcast.add_def({ reg: Virtual(int_val) })
    bitcast.add_use(Virtual(val_vreg))
    block.add_inst(bitcast)
    int_val
  } else {
    val_vreg
  }
  // Call: gc_struct_set_impl(ref, type_idx, field_idx, value)
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, field_idx_vreg, actual_val_vreg],
    None,
  )
}

///|
/// Lower array.new: Allocate array with init value and length
/// Uses runtime libcall: gc_array_new_impl(type_idx, length, init_value) -> array_ref
fn lower_array_new(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let init_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let len_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  // Materialize type_idx
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArrayNew))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Check if init value is float - C libcall expects int64, need bitcast
  let is_float = inst.operands[0].ty is (@ir.Type::F32 | @ir.Type::F64)
  let actual_init_vreg = if is_float {
    let int_val = ctx.vcode_func.new_vreg(Int)
    let bitcast = @instr.VCodeInst::new(Bitcast)
    bitcast.add_def({ reg: Virtual(int_val) })
    bitcast.add_use(Virtual(init_vreg))
    block.add_inst(bitcast)
    int_val
  } else {
    init_vreg
  }
  // Call: gc_array_new_impl(type_idx, length, init_value) -> result
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [type_idx_vreg, len_vreg, actual_init_vreg],
    Some(dst),
  )
}

///|
/// Lower array.new_default: Allocate array with default values
/// Uses runtime libcall: gc_array_new_impl(type_idx, length, init_value=0) -> array_ref
fn lower_array_new_default(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let len_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Load default value (0) for the init value
  let zero_vreg = materialize_imm(ctx, block, 0L)
  // Materialize type_idx
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArrayNew))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_array_new_impl(type_idx, length, init_value) -> result
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [type_idx_vreg, len_vreg, zero_vreg],
    Some(dst),
  )
}

///|
/// Lower array.new_fixed: Allocate fixed-size array with element values
/// Uses runtime libcalls: gc_array_new_impl and gc_array_set_impl
fn lower_array_new_fixed(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
  len : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  // Materialize common values
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  let len_vreg = materialize_imm(ctx, block, len.to_int64())

  // Load ArrayNew function pointer (we'll need it for the initial allocation)
  let array_new_fp = ctx.vcode_func.new_vreg(Int)
  let load_new_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArrayNew))
  load_new_fp.add_def({ reg: Virtual(array_new_fp) })
  block.add_inst(load_new_fp)
  if len == 0 {
    // Empty array - use zero init and length 0
    let zero_vreg = materialize_imm(ctx, block, 0L)
    // Call: gc_array_new_impl(type_idx, length=0, init_value=0) -> result
    lower_c_libcall(
      ctx,
      block,
      array_new_fp,
      [type_idx_vreg, zero_vreg, zero_vreg],
      Some(dst),
    )
  } else {
    // Check if element type is float
    let is_float = inst.operands[0].ty is (@ir.Type::F32 | @ir.Type::F64)
    // Create array with first element
    let first_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
    let actual_first = if is_float {
      let int_val = ctx.vcode_func.new_vreg(Int)
      let bitcast = @instr.VCodeInst::new(Bitcast)
      bitcast.add_def({ reg: Virtual(int_val) })
      bitcast.add_use(Virtual(first_vreg))
      block.add_inst(bitcast)
      int_val
    } else {
      first_vreg
    }
    // Call: gc_array_new_impl(type_idx, length, init_value) -> result
    lower_c_libcall(
      ctx,
      block,
      array_new_fp,
      [type_idx_vreg, len_vreg, actual_first],
      Some(dst),
    )
    // Set remaining elements using gc_array_set_impl
    if len > 1 {
      // Load ArraySet function pointer once for all set operations
      let array_set_fp = ctx.vcode_func.new_vreg(Int)
      let load_set_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArraySet))
      load_set_fp.add_def({ reg: Virtual(array_set_fp) })
      block.add_inst(load_set_fp)
      for i in 1..<len {
        let elem_vreg = ctx.get_vreg_for_use(inst.operands[i], block)
        let actual_elem = if is_float {
          let int_val = ctx.vcode_func.new_vreg(Int)
          let bitcast = @instr.VCodeInst::new(Bitcast)
          bitcast.add_def({ reg: Virtual(int_val) })
          bitcast.add_use(Virtual(elem_vreg))
          block.add_inst(bitcast)
          int_val
        } else {
          elem_vreg
        }
        let idx_vreg = materialize_imm(ctx, block, i.to_int64())
        // Call: gc_array_set_impl(ref, type_idx, idx, value)
        lower_c_libcall(
          ctx,
          block,
          array_set_fp,
          [dst, type_idx_vreg, idx_vreg, actual_elem],
          None,
        )
      }
    }
  }
}

///|
/// Lower array.get: Get array element
/// Uses runtime libcall: gc_array_get_impl(ref, type_idx, idx) -> value
fn lower_array_get(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let idx_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  // Materialize type_idx
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArrayGet))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Check if result is a float type - C libcall returns int64, need bitcast
  let is_float = result.ty is (@ir.Type::F32 | @ir.Type::F64)
  if is_float {
    // For float results: call returns int64, then bitcast to float
    let int_result = ctx.vcode_func.new_vreg(Int)
    lower_c_libcall(
      ctx,
      block,
      func_ptr_vreg,
      [ref_vreg, type_idx_vreg, idx_vreg],
      Some(int_result),
    )
    // Bitcast from int to float
    let bitcast = @instr.VCodeInst::new(Bitcast)
    bitcast.add_def({ reg: Virtual(dst) })
    bitcast.add_use(Virtual(int_result))
    block.add_inst(bitcast)
  } else {
    // For integer results: call returns directly
    lower_c_libcall(
      ctx,
      block,
      func_ptr_vreg,
      [ref_vreg, type_idx_vreg, idx_vreg],
      Some(dst),
    )
  }
}

///|
/// Lower array.get_s: Get array element with sign extension
/// Uses runtime libcall then sign extends based on byte_width
fn lower_array_get_s(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
  byte_width : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let idx_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  // Materialize type_idx
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArrayGet))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call and get raw value
  let raw_result = ctx.vcode_func.new_vreg(Int)
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, idx_vreg],
    Some(raw_result),
  )
  // Sign extend based on byte_width
  if byte_width == 1 {
    let ext = @instr.VCodeInst::new(Extend(Signed8To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else if byte_width == 2 {
    let ext = @instr.VCodeInst::new(Extend(Signed16To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else {
    let mov = @instr.VCodeInst::new(Move)
    mov.add_def({ reg: Virtual(dst) })
    mov.add_use(Virtual(raw_result))
    block.add_inst(mov)
  }
}

///|
/// Lower array.get_u: Get array element with zero extension
/// Uses runtime libcall then zero extends based on byte_width
fn lower_array_get_u(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
  byte_width : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let idx_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  // Materialize type_idx
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArrayGet))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call and get raw value
  let raw_result = ctx.vcode_func.new_vreg(Int)
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, idx_vreg],
    Some(raw_result),
  )
  // Zero extend based on byte_width
  if byte_width == 1 {
    let ext = @instr.VCodeInst::new(Extend(Unsigned8To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else if byte_width == 2 {
    let ext = @instr.VCodeInst::new(Extend(Unsigned16To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else {
    let mov = @instr.VCodeInst::new(Move)
    mov.add_def({ reg: Virtual(dst) })
    mov.add_use(Virtual(raw_result))
    block.add_inst(mov)
  }
}

///|
/// Lower array.set: Set array element
/// Uses runtime libcall: gc_array_set_impl(ref, type_idx, idx, value)
fn lower_array_set(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  type_idx : Int,
) -> Unit {
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let idx_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  let val_vreg = ctx.get_vreg_for_use(inst.operands[2], block)
  // Materialize type_idx
  let type_idx_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArraySet))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Check if value is a float type - C libcall expects int64, need bitcast
  let is_float = inst.operands[2].ty is (@ir.Type::F32 | @ir.Type::F64)
  let actual_val_vreg = if is_float {
    // For float values: bitcast to int before passing to C function
    let int_val = ctx.vcode_func.new_vreg(Int)
    let bitcast = @instr.VCodeInst::new(Bitcast)
    bitcast.add_def({ reg: Virtual(int_val) })
    bitcast.add_use(Virtual(val_vreg))
    block.add_inst(bitcast)
    int_val
  } else {
    val_vreg
  }
  // Call: gc_array_set_impl(ref, type_idx, idx, value)
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, idx_vreg, actual_val_vreg],
    None,
  )
}

///|
/// Lower array.len: Get array length
/// Uses runtime libcall: gc_array_len_impl(ref) -> length
fn lower_array_len(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArrayLen))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_array_len_impl(ref) -> result
  lower_c_libcall(ctx, block, func_ptr_vreg, [ref_vreg], Some(dst))
}

///|
/// Lower array.fill: Fill array elements with a value
/// Uses runtime libcall: gc_array_fill_impl(ref, offset, value, count)
fn lower_array_fill(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  _type_idx : Int,
) -> Unit {
  // Operands: ref, offset, value, count
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let offset_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  let val_vreg = ctx.get_vreg_for_use(inst.operands[2], block)
  let count_vreg = ctx.get_vreg_for_use(inst.operands[3], block)
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArrayFill))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_array_fill_impl(ref, offset, value, count)
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, offset_vreg, val_vreg, count_vreg],
    None,
  )
}

///|
/// Lower array.copy: Copy elements between arrays
/// Uses runtime libcall: gc_array_copy_impl(dst_ref, dst_off, src_ref, src_off, count)
fn lower_array_copy(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  _dst_type : Int,
  _src_type : Int,
) -> Unit {
  // Operands: dst_ref, dst_offset, src_ref, src_offset, count
  let dst_ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let dst_off_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  let src_ref_vreg = ctx.get_vreg_for_use(inst.operands[2], block)
  let src_off_vreg = ctx.get_vreg_for_use(inst.operands[3], block)
  let count_vreg = ctx.get_vreg_for_use(inst.operands[4], block)
  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadGCFuncPtr(ArrayCopy))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_array_copy_impl(dst_ref, dst_off, src_ref, src_off, count)
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [dst_ref_vreg, dst_off_vreg, src_ref_vreg, src_off_vreg, count_vreg],
    None,
  )
}
