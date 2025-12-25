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
