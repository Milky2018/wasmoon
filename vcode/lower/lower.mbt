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
struct LoweringContext {
  ir_func : @ir.Function
  vcode_func : @regalloc.VCodeFunction
  abi_settings : @abi.ABISettings
  num_imports : Int
  // Map from IR Value id to @abi.VReg
  value_map : Map[Int, @abi.VReg]
  // Map from IR Block id to VCode block id
  block_map : Map[Int, Int]
  // Map from IR Value id to stack param index (for params >= 8)
  stack_param_map : Map[Int, (Int, @abi.RegClass)]
  // Cache of func_table base per VCode block (block-local CSE)
  func_table_cache : Map[Int, @abi.VReg]
  // Set of Icmp result value IDs that are exclusively used by Select (will be fused)
  fused_icmps : @hashset.HashSet[Int]
  // Use counts for IR values (used to skip unused call results)
  use_counts : Map[Int, Int]
}

///|
pub fn LoweringContext::new(
  ir_func : @ir.Function,
  abi_settings : @abi.ABISettings,
  num_imports : Int,
) -> LoweringContext {
  let use_counts = compute_use_counts(ir_func)
  {
    ir_func,
    vcode_func: @regalloc.VCodeFunction::new(ir_func.name),
    abi_settings,
    num_imports,
    value_map: {},
    block_map: {},
    stack_param_map: {},
    func_table_cache: {},
    fused_icmps: @hashset.new(),
    use_counts,
  }
}

///|
/// Compute use counts for each IR value.
fn compute_use_counts(ir_func : @ir.Function) -> Map[Int, Int] {
  let use_counts : Map[Int, Int] = {}
  for block in ir_func.blocks {
    for inst in block.instructions {
      for op in inst.operands {
        let count = use_counts.get(op.id).unwrap_or(0)
        use_counts.set(op.id, count + 1)
      }
    }
    // Also count uses in terminators
    if block.terminator is Some(term) {
      let term_uses = match term {
        @ir.Terminator::Brz(cond, _, _) | @ir.Terminator::Brnz(cond, _, _) =>
          [cond]
        @ir.Terminator::BrTable(index, _, _) => [index]
        @ir.Terminator::Jump(_, args) | @ir.Terminator::Return(args) => args
        @ir.Terminator::Trap(_) => []
      }
      for v in term_uses {
        let count = use_counts.get(v.id).unwrap_or(0)
        use_counts.set(v.id, count + 1)
      }
    }
  }
  use_counts
}

///|
/// Compute which Icmp results are exclusively used by Select/branch and can be fused.
/// This allows lower_icmp to skip emitting redundant Cmp instructions.
fn compute_fused_icmps(
  ir_func : @ir.Function,
  use_counts : Map[Int, Int],
) -> @hashset.HashSet[Int] {
  // Find Icmp results that have exactly one use in a Select or branch
  let fused : @hashset.HashSet[Int] = @hashset.new()
  for block in ir_func.blocks {
    for inst in block.instructions {
      // Check if this is a Select instruction
      if inst.opcode is @ir.Opcode::Select {
        let cond = inst.operands[0]
        // Check if the condition is an Icmp result with exactly one use
        if use_counts.get(cond.id).unwrap_or(0) == 1 {
          // Find the defining instruction of the condition
          for b in ir_func.blocks {
            for i in b.instructions {
              if i.first_result() is Some(r) && r.id == cond.id {
                // Check if it's an Icmp
                if i.opcode is @ir.Opcode::Icmp(_) {
                  fused.add(cond.id)
                }
              }
            }
          }
        }
      }
    }
    if block.terminator is Some(term) {
      match term {
        @ir.Terminator::Brz(cond, _, _) | @ir.Terminator::Brnz(cond, _, _) =>
          // Check if the condition is an Icmp result with exactly one use
          if use_counts.get(cond.id).unwrap_or(0) == 1 {
            // Find the defining instruction of the condition
            for b in ir_func.blocks {
              for i in b.instructions {
                if i.first_result() is Some(r) && r.id == cond.id {
                  // Check if it's an Icmp
                  if i.opcode is @ir.Opcode::Icmp(_) {
                    fused.add(cond.id)
                  }
                }
              }
            }
          }
        _ => ()
      }
    }
  }
  fused
}

///|
/// Collect call result vregs, skipping all results if none are used.
fn collect_call_result_vregs(
  ctx : LoweringContext,
  inst : @ir.Inst,
) -> Array[@abi.VReg] {
  let mut any_used = false
  for result in inst.all_results() {
    if ctx.use_counts.get(result.id).unwrap_or(0) > 0 {
      any_used = true
      break
    }
  }
  let result_vregs : Array[@abi.VReg] = []
  if !any_used {
    return result_vregs
  }
  for result in inst.all_results() {
    result_vregs.push(ctx.get_vreg(result))
  }
  result_vregs
}

///|
/// Return a rematerializable constant for a call argument if it's a single-use const.
fn try_collect_call_arg_const(
  ctx : LoweringContext,
  value : @ir.Value,
) -> CallConstArg? {
  if ctx.use_counts.get(value.id).unwrap_or(0) != 1 {
    return None
  }
  if find_defining_inst(ctx, value) is Some(inst) {
    match inst.opcode {
      @ir.Opcode::Iconst(v) => Some(CallConstArg::Int(v))
      @ir.Opcode::Fconst(v) =>
        match value.ty {
          @ir.Type::F32 =>
            Some(CallConstArg::F32(v.reinterpret_as_int64().to_int()))
          @ir.Type::F64 => Some(CallConstArg::F64(v.reinterpret_as_int64()))
          _ => None
        }
      _ => None
    }
  } else {
    None
  }
}

///|
/// Collect call arguments and rematerializable constants.
fn collect_call_args_with_consts(
  ctx : LoweringContext,
  operands : Array[@ir.Value],
  block : @block.VCodeBlock,
  start_idx : Int,
) -> (Array[@abi.VReg], Map[Int, CallConstArg]) {
  let arg_vregs : Array[@abi.VReg] = []
  let const_args : Map[Int, CallConstArg] = {}
  for i in start_idx..<operands.length() {
    let operand = operands[i]
    if try_collect_call_arg_const(ctx, operand) is Some(value) {
      let class = ir_type_to_reg_class(operand.ty)
      let vreg = ctx.new_vreg(class)
      arg_vregs.push(vreg)
      const_args.set(vreg.id, value)
    } else {
      arg_vregs.push(ctx.get_vreg_for_use(operand, block))
    }
  }
  (arg_vregs, const_args)
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
  if self.stack_param_map.get(value.id) is Some((offset, class)) {
    // Generate LoadStackParam instruction
    let result = self.vcode_func.new_vreg(class)
    let inst = @instr.VCodeInst::new(LoadStackParam(offset, class))
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
    @ir.Type::V128 => Vector // SIMD uses vector register class
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
    @ir.Type::V128 => V128
    // Reference types use 64-bit storage (0 as null)
    @ir.Type::FuncRef | @ir.Type::ExternRef => I64
  }
}

// ============ Pattern Matching Helpers for AArch64 Instruction Selection ============

///|
/// Check if a value is defined by a shift-left instruction with a constant
/// Returns (shifted_value, shift_amount) if matched
/// The shift amount is masked according to WebAssembly semantics:
/// - i32: amount & 31
/// - i64: amount & 63
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
      // Determine mask based on value type (i32 uses 31, i64 uses 63)
      let is_64 = value.ty is @ir.Type::I64
      let mask = if is_64 { 63 } else { 31 }
      let shift_val = amount.to_int() & mask
      // shift_val is now guaranteed to be in valid range after masking
      return Some((inst.operands[0], shift_val))
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
/// Check if a value is a constant and return the value if valid for ADD/SUB immediate
/// Returns Some(val) if the value is a constant in valid 12-bit immediate range
fn match_add_imm_value(ctx : LoweringContext, value : @ir.Value) -> Int64? {
  if find_defining_inst(ctx, value) is Some(inst) &&
    inst.opcode is @ir.Opcode::Iconst(val) {
    if is_valid_add_imm(val) {
      return Some(val)
    }
  }
  None
}

///|
/// Check if a value is iadd(base, iconst(offset)) and return (base, offset) if matched
/// Used for folding address calculations into load/store instructions
fn match_iadd_const(
  ctx : LoweringContext,
  value : @ir.Value,
) -> (@ir.Value, Int64)? {
  if find_defining_inst(ctx, value) is Some(inst) &&
    inst.opcode is @ir.Opcode::Iadd {
    // Check if second operand is a constant
    if find_defining_inst(ctx, inst.operands[1]) is Some(const_inst) &&
      const_inst.opcode is @ir.Opcode::Iconst(offset) {
      return Some((inst.operands[0], offset))
    }
    // Also check first operand (iadd is commutative)
    if find_defining_inst(ctx, inst.operands[0]) is Some(const_inst) &&
      const_inst.opcode is @ir.Opcode::Iconst(offset) {
      return Some((inst.operands[1], offset))
    }
  }
  None
}

///|
/// Check if an offset is valid for AArch64 LDR/STR unsigned immediate
/// offset must be non-negative, aligned to access_size, and fit in 12-bit scaled
fn is_valid_load_store_offset(offset : Int64, access_size : Int) -> Bool {
  if offset < 0L {
    return false
  }
  // Check alignment
  if offset % access_size.to_int64() != 0L {
    return false
  }
  // Check scaled offset fits in 12 bits (max 4095 * access_size)
  let max_offset = 4095L * access_size.to_int64()
  offset <= max_offset
}

///|
/// Check if a value is the result of an Icmp instruction
/// Returns (lhs, rhs, condition) if matched
fn match_icmp_value(
  ctx : LoweringContext,
  value : @ir.Value,
) -> (@ir.Value, @ir.Value, @ir.IntCC)? {
  if find_defining_inst(ctx, value) is Some(inst) &&
    inst.opcode is @ir.Opcode::Icmp(cc) {
    return Some((inst.operands[0], inst.operands[1], cc))
  }
  None
}

///|
/// Convert IR IntCC to VCode Cond for conditional branches
fn intcc_to_cond(cc : @ir.IntCC) -> @instr.Cond {
  match cc {
    Eq => @instr.Cond::Eq
    Ne => @instr.Cond::Ne
    Slt => @instr.Cond::Lt
    Sle => @instr.Cond::Le
    Sgt => @instr.Cond::Gt
    Sge => @instr.Cond::Ge
    Ult => @instr.Cond::Lo
    Ule => @instr.Cond::Ls
    Ugt => @instr.Cond::Hi
    Uge => @instr.Cond::Hs
  }
}

///|
/// Lower an entire IR function to VCode
pub fn lower_function(
  ir_func : @ir.Function,
  abi_settings? : @abi.ABISettings = @abi.ABISettings::default(),
  num_imports? : Int = -1,
) -> @regalloc.VCodeFunction {
  // Apply e-graph optimization before lowering (constant folding, uextend(const) -> const, etc.)
  @ir.optimize_function(ir_func) |> ignore
  let ctx = LoweringContext::new(ir_func, abi_settings, num_imports)

  // Phase 0: Pre-compute which Icmps can be fused with Select
  let fused = compute_fused_icmps(ir_func, ctx.use_counts)
  for id in fused {
    ctx.fused_icmps.add(id)
  }

  // Phase 1: Create VCode blocks and set up block mapping
  for ir_block in ir_func.blocks {
    let vcode_block = ctx.vcode_func.new_block()
    ctx.block_map.set(ir_block.id, vcode_block.id)
  }

  // Phase 2: Lower function parameters
  // ABI: params[0] is vmctx (X0), then normal AAPCS64-style assignment:
  // - int params: X0-X7 (vmctx consumes X0)
  // - float params: V0-V7
  // - overflow: int overflow first, then float overflow
  let max_int_reg_params = @abi.MAX_REG_PARAMS // X0-X7 (includes vmctx which ARE in ir_func.params)
  let max_float_reg_params = @abi.MAX_FLOAT_REG_PARAMS // V0-V7
  let mut int_reg_count = 0
  let mut float_reg_count = 0
  let int_stack_values : Array[@ir.Value] = []
  let float_stack_values : Array[(@ir.Value, @abi.RegClass)] = []
  let float_stack_classes : Array[@abi.RegClass] = []
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
          // Stack parameter: laid out in overflow area (entry SP).
          int_stack_values.push(value)
        }
      Float32 | Float64 | Vector =>
        // Vector uses same V0-V7 registers as floats on AArch64
        if float_reg_count < max_float_reg_params {
          // Register parameter: allocate @abi.VReg
          let vreg = ctx.vcode_func.add_param(class)
          ctx.value_map.set(value.id, vreg)
          float_reg_count = float_reg_count + 1
        } else {
          float_stack_values.push((value, class))
          float_stack_classes.push(class)
        }
    }
  }
  let (int_offsets, float_offsets, _) = @abi.wasm_layout_overflow_stack(
    int_stack_values.length(),
    float_stack_classes,
  )
  for i in 0..<int_stack_values.length() {
    ctx.stack_param_map.set(int_stack_values[i].id, (int_offsets[i], Int))
  }
  for i in 0..<float_stack_values.length() {
    let (value, class) = float_stack_values[i]
    ctx.stack_param_map.set(value.id, (float_offsets[i], class))
  }
  ctx.vcode_func.set_int_stack_params(int_stack_values.length())

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

  // Phase 5: Peephole optimization
  optimize_vcode(ctx.vcode_func)
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
    @ir.Opcode::Umulh => lower_umulh(ctx, inst, block)
    @ir.Opcode::Smulh => lower_smulh(ctx, inst, block)
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
    @ir.Opcode::Bnot =>
      lower_unary_int(ctx, inst, block, fn(is_64) { Not(is_64) })

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

    // Note: Load/Store opcodes removed - now desugared via FuncEnvironment to LoadPtr/StorePtr

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

    // Memory management (with memidx for multi-memory support)
    @ir.Opcode::LoadMemBase(memidx) =>
      lower_load_mem_base(ctx, inst, block, memidx)
    @ir.Opcode::MemoryGrow(memidx, max_pages) =>
      lower_memory_grow(ctx, inst, block, memidx, max_pages)
    @ir.Opcode::MemorySize(memidx) =>
      lower_memory_size(ctx, inst, block, memidx)
    @ir.Opcode::MemoryFill(memidx) =>
      lower_memory_fill(ctx, inst, block, memidx)
    @ir.Opcode::MemoryCopy(dst_memidx, src_memidx) =>
      lower_memory_copy(ctx, inst, block, dst_memidx, src_memidx)
    @ir.Opcode::MemoryInit(memidx, data_idx) =>
      lower_memory_init(ctx, inst, block, memidx, data_idx)
    @ir.Opcode::DataDrop(data_idx) =>
      lower_data_drop(ctx, inst, block, data_idx)

    // Table operations
    // NOTE: TableGet, TableSet, TableSize are desugared via FuncEnvironment at IR level
    @ir.Opcode::TableGrow(table_idx) =>
      lower_table_grow(ctx, inst, block, table_idx)
    @ir.Opcode::TableFill(table_idx) =>
      lower_table_fill(ctx, inst, block, table_idx)
    @ir.Opcode::TableCopy(dst_table_idx, src_table_idx) =>
      lower_table_copy(ctx, inst, block, dst_table_idx, src_table_idx)
    @ir.Opcode::TableInit(table_idx, elem_idx) =>
      lower_table_init(ctx, inst, block, table_idx, elem_idx)
    @ir.Opcode::ElemDrop(elem_idx) =>
      lower_elem_drop(ctx, inst, block, elem_idx)

    // NOTE: GlobalGet, GlobalSet are desugared via FuncEnvironment at IR level

    // Function calls
    @ir.Opcode::Call(func_idx) => lower_call(ctx, inst, block, func_idx)
    @ir.Opcode::CallIndirect(type_idx, table_idx) =>
      lower_call_indirect(ctx, inst, block, type_idx, table_idx)
    @ir.Opcode::CallRef(type_idx) => lower_call_ref(ctx, inst, block, type_idx)
    // Tail calls - use dedicated lowering functions with Standard parameter handling
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
    @ir.Opcode::LoadPtrNarrow(result_ty, bits, signed) =>
      lower_load_ptr_narrow(ctx, inst, block, result_ty, bits, signed)
    @ir.Opcode::StorePtrNarrow(bits) =>
      lower_store_ptr_narrow(ctx, inst, block, bits)
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
    @ir.Opcode::ArrayNewData(type_idx, data_idx) =>
      lower_array_new_data(ctx, inst, block, type_idx, data_idx)
    @ir.Opcode::ArrayNewElem(type_idx, elem_idx) =>
      lower_array_new_elem(ctx, inst, block, type_idx, elem_idx)
    @ir.Opcode::ArrayInitData(type_idx, data_idx) =>
      lower_array_init_data(ctx, inst, block, type_idx, data_idx)
    @ir.Opcode::ArrayInitElem(type_idx, elem_idx) =>
      lower_array_init_elem(ctx, inst, block, type_idx, elem_idx)
    @ir.Opcode::RefTest(type_idx, nullable) =>
      lower_ref_test(ctx, inst, block, type_idx, nullable)
    @ir.Opcode::RefCast(type_idx, nullable) =>
      lower_ref_cast(ctx, inst, block, type_idx, nullable)
    @ir.Opcode::RefEq => lower_ref_eq(ctx, inst, block)

    // Exception handling operations
    @ir.Opcode::Throw(tag_idx) => lower_throw(ctx, inst, block, tag_idx)
    @ir.Opcode::ThrowRef => lower_throw_ref(ctx, inst, block)
    @ir.Opcode::TryTableBegin(handler_id) =>
      lower_try_table_begin(ctx, inst, block, handler_id)
    @ir.Opcode::TryTableEnd(handler_id) =>
      lower_try_table_end(ctx, inst, block, handler_id)
    @ir.Opcode::GetExceptionTag => lower_get_exception_tag(ctx, inst, block)
    @ir.Opcode::GetExceptionValue(idx) =>
      lower_get_exception_value(ctx, inst, block, idx)
    @ir.Opcode::GetExceptionValueCount =>
      lower_get_exception_value_count(ctx, inst, block)
    @ir.Opcode::Delegate(depth) => lower_delegate(ctx, inst, block, depth)
    @ir.Opcode::SpillLocalsForThrow(count) =>
      lower_spill_locals_for_throw(ctx, inst, block, count)
    @ir.Opcode::GetSpilledLocal(idx) =>
      lower_get_spilled_local(ctx, inst, block, idx)

    // SIMD operations
    @ir.Opcode::V128Const(bytes) => lower_v128_const(ctx, inst, block, bytes)
    @ir.Opcode::V128Splat8 => lower_v128_splat(ctx, inst, block, B8)
    @ir.Opcode::V128Splat16 => lower_v128_splat(ctx, inst, block, H16)
    @ir.Opcode::V128Splat32 => lower_v128_splat(ctx, inst, block, S32)
    @ir.Opcode::V128Splat64 => lower_v128_splat(ctx, inst, block, D64)
    @ir.Opcode::V128SplatF32 => lower_v128_splat_f(ctx, inst, block, true)
    @ir.Opcode::V128SplatF64 => lower_v128_splat_f(ctx, inst, block, false)
    @ir.Opcode::V128ExtractLane8S(lane) =>
      lower_v128_extract_s(ctx, inst, block, B8, lane)
    @ir.Opcode::V128ExtractLane8U(lane) =>
      lower_v128_extract_u(ctx, inst, block, B8, lane)
    @ir.Opcode::V128ExtractLane16S(lane) =>
      lower_v128_extract_s(ctx, inst, block, H16, lane)
    @ir.Opcode::V128ExtractLane16U(lane) =>
      lower_v128_extract_u(ctx, inst, block, H16, lane)
    @ir.Opcode::V128ExtractLane32(lane) =>
      lower_v128_extract_u(ctx, inst, block, S32, lane)
    @ir.Opcode::V128ExtractLane64(lane) =>
      lower_v128_extract_u(ctx, inst, block, D64, lane)
    @ir.Opcode::V128ExtractLaneF32(lane) =>
      lower_v128_extract_f(ctx, inst, block, true, lane)
    @ir.Opcode::V128ExtractLaneF64(lane) =>
      lower_v128_extract_f(ctx, inst, block, false, lane)
    @ir.Opcode::V128ReplaceLane8(lane) =>
      lower_v128_replace(ctx, inst, block, B8, lane)
    @ir.Opcode::V128ReplaceLane16(lane) =>
      lower_v128_replace(ctx, inst, block, H16, lane)
    @ir.Opcode::V128ReplaceLane32(lane) =>
      lower_v128_replace(ctx, inst, block, S32, lane)
    @ir.Opcode::V128ReplaceLane64(lane) =>
      lower_v128_replace(ctx, inst, block, D64, lane)
    @ir.Opcode::V128ReplaceLaneF32(lane) =>
      lower_v128_replace_f(ctx, inst, block, true, lane)
    @ir.Opcode::V128ReplaceLaneF64(lane) =>
      lower_v128_replace_f(ctx, inst, block, false, lane)
    @ir.Opcode::V128Shuffle(lanes) =>
      lower_v128_shuffle(ctx, inst, block, lanes)
    @ir.Opcode::V128Swizzle => lower_v128_swizzle(ctx, inst, block)

    // Bitwise operations
    @ir.Opcode::V128Not => lower_v128_unary(ctx, inst, block, SIMDNot)
    @ir.Opcode::V128And => lower_v128_binary(ctx, inst, block, SIMDAnd)
    @ir.Opcode::V128AndNot => lower_v128_binary(ctx, inst, block, SIMDBic)
    @ir.Opcode::V128Or => lower_v128_binary(ctx, inst, block, SIMDOr)
    @ir.Opcode::V128Xor => lower_v128_binary(ctx, inst, block, SIMDXor)
    @ir.Opcode::V128Bitselect => lower_v128_ternary(ctx, inst, block, SIMDBsl)

    // Any/All true, Bitmask
    @ir.Opcode::V128AnyTrue => lower_v128_to_i32(ctx, inst, block, SIMDAnyTrue)
    @ir.Opcode::V128AllTrue8 =>
      lower_v128_to_i32(ctx, inst, block, SIMDAllTrue(B8))
    @ir.Opcode::V128AllTrue16 =>
      lower_v128_to_i32(ctx, inst, block, SIMDAllTrue(H16))
    @ir.Opcode::V128AllTrue32 =>
      lower_v128_to_i32(ctx, inst, block, SIMDAllTrue(S32))
    @ir.Opcode::V128AllTrue64 =>
      lower_v128_to_i32(ctx, inst, block, SIMDAllTrue(D64))
    @ir.Opcode::V128Bitmask8 =>
      lower_v128_to_i32(ctx, inst, block, SIMDBitmask(B8))
    @ir.Opcode::V128Bitmask16 =>
      lower_v128_to_i32(ctx, inst, block, SIMDBitmask(H16))
    @ir.Opcode::V128Bitmask32 =>
      lower_v128_to_i32(ctx, inst, block, SIMDBitmask(S32))
    @ir.Opcode::V128Bitmask64 =>
      lower_v128_to_i32(ctx, inst, block, SIMDBitmask(D64))

    // Integer arithmetic
    @ir.Opcode::V128Add8 => lower_v128_binary(ctx, inst, block, SIMDAdd(B8))
    @ir.Opcode::V128Add16 => lower_v128_binary(ctx, inst, block, SIMDAdd(H16))
    @ir.Opcode::V128Add32 => lower_v128_binary(ctx, inst, block, SIMDAdd(S32))
    @ir.Opcode::V128Add64 => lower_v128_binary(ctx, inst, block, SIMDAdd(D64))
    @ir.Opcode::V128Sub8 => lower_v128_binary(ctx, inst, block, SIMDSub(B8))
    @ir.Opcode::V128Sub16 => lower_v128_binary(ctx, inst, block, SIMDSub(H16))
    @ir.Opcode::V128Sub32 => lower_v128_binary(ctx, inst, block, SIMDSub(S32))
    @ir.Opcode::V128Sub64 => lower_v128_binary(ctx, inst, block, SIMDSub(D64))
    @ir.Opcode::V128Mul16 => lower_v128_binary(ctx, inst, block, SIMDMul(H16))
    @ir.Opcode::V128Mul32 => lower_v128_binary(ctx, inst, block, SIMDMul(S32))
    @ir.Opcode::V128Mul64 => lower_v128_binary(ctx, inst, block, SIMDMul(D64))

    // Saturating arithmetic
    @ir.Opcode::V128AddSat8S =>
      lower_v128_binary(ctx, inst, block, SIMDSqadd(B8))
    @ir.Opcode::V128AddSat8U =>
      lower_v128_binary(ctx, inst, block, SIMDUqadd(B8))
    @ir.Opcode::V128AddSat16S =>
      lower_v128_binary(ctx, inst, block, SIMDSqadd(H16))
    @ir.Opcode::V128AddSat16U =>
      lower_v128_binary(ctx, inst, block, SIMDUqadd(H16))
    @ir.Opcode::V128SubSat8S =>
      lower_v128_binary(ctx, inst, block, SIMDSqsub(B8))
    @ir.Opcode::V128SubSat8U =>
      lower_v128_binary(ctx, inst, block, SIMDUqsub(B8))
    @ir.Opcode::V128SubSat16S =>
      lower_v128_binary(ctx, inst, block, SIMDSqsub(H16))
    @ir.Opcode::V128SubSat16U =>
      lower_v128_binary(ctx, inst, block, SIMDUqsub(H16))

    // Min/Max
    @ir.Opcode::V128Min8S => lower_v128_binary(ctx, inst, block, SIMDSmin(B8))
    @ir.Opcode::V128Min8U => lower_v128_binary(ctx, inst, block, SIMDUmin(B8))
    @ir.Opcode::V128Min16S => lower_v128_binary(ctx, inst, block, SIMDSmin(H16))
    @ir.Opcode::V128Min16U => lower_v128_binary(ctx, inst, block, SIMDUmin(H16))
    @ir.Opcode::V128Min32S => lower_v128_binary(ctx, inst, block, SIMDSmin(S32))
    @ir.Opcode::V128Min32U => lower_v128_binary(ctx, inst, block, SIMDUmin(S32))
    @ir.Opcode::V128Max8S => lower_v128_binary(ctx, inst, block, SIMDSmax(B8))
    @ir.Opcode::V128Max8U => lower_v128_binary(ctx, inst, block, SIMDUmax(B8))
    @ir.Opcode::V128Max16S => lower_v128_binary(ctx, inst, block, SIMDSmax(H16))
    @ir.Opcode::V128Max16U => lower_v128_binary(ctx, inst, block, SIMDUmax(H16))
    @ir.Opcode::V128Max32S => lower_v128_binary(ctx, inst, block, SIMDSmax(S32))
    @ir.Opcode::V128Max32U => lower_v128_binary(ctx, inst, block, SIMDUmax(S32))

    // Average
    @ir.Opcode::V128Avgr8U =>
      lower_v128_binary(ctx, inst, block, SIMDUrhadd(B8))
    @ir.Opcode::V128Avgr16U =>
      lower_v128_binary(ctx, inst, block, SIMDUrhadd(H16))

    // Unary operations
    @ir.Opcode::V128Abs8 => lower_v128_unary(ctx, inst, block, SIMDAbs(B8))
    @ir.Opcode::V128Abs16 => lower_v128_unary(ctx, inst, block, SIMDAbs(H16))
    @ir.Opcode::V128Abs32 => lower_v128_unary(ctx, inst, block, SIMDAbs(S32))
    @ir.Opcode::V128Abs64 => lower_v128_unary(ctx, inst, block, SIMDAbs(D64))
    @ir.Opcode::V128Neg8 => lower_v128_unary(ctx, inst, block, SIMDNeg(B8))
    @ir.Opcode::V128Neg16 => lower_v128_unary(ctx, inst, block, SIMDNeg(H16))
    @ir.Opcode::V128Neg32 => lower_v128_unary(ctx, inst, block, SIMDNeg(S32))
    @ir.Opcode::V128Neg64 => lower_v128_unary(ctx, inst, block, SIMDNeg(D64))
    @ir.Opcode::V128Popcnt8 => lower_v128_unary(ctx, inst, block, SIMDCnt)

    // Shifts - split into SIMDBroadcastShift + SIMDShiftByVec
    // lower_v128_shift(ctx, inst, block, lane_size, negate, use_ushl)
    @ir.Opcode::V128Shl8 => lower_v128_shift(ctx, inst, block, B8, false, false)
    @ir.Opcode::V128Shl16 =>
      lower_v128_shift(ctx, inst, block, H16, false, false)
    @ir.Opcode::V128Shl32 =>
      lower_v128_shift(ctx, inst, block, S32, false, false)
    @ir.Opcode::V128Shl64 =>
      lower_v128_shift(ctx, inst, block, D64, false, false)
    @ir.Opcode::V128Shr8S => lower_v128_shift(ctx, inst, block, B8, true, false)
    @ir.Opcode::V128Shr8U => lower_v128_shift(ctx, inst, block, B8, true, true)
    @ir.Opcode::V128Shr16S =>
      lower_v128_shift(ctx, inst, block, H16, true, false)
    @ir.Opcode::V128Shr16U =>
      lower_v128_shift(ctx, inst, block, H16, true, true)
    @ir.Opcode::V128Shr32S =>
      lower_v128_shift(ctx, inst, block, S32, true, false)
    @ir.Opcode::V128Shr32U =>
      lower_v128_shift(ctx, inst, block, S32, true, true)
    @ir.Opcode::V128Shr64S =>
      lower_v128_shift(ctx, inst, block, D64, true, false)
    @ir.Opcode::V128Shr64U =>
      lower_v128_shift(ctx, inst, block, D64, true, true)

    // Comparisons
    @ir.Opcode::V128Eq8 => lower_v128_binary(ctx, inst, block, SIMDCmp(B8, Eq))
    @ir.Opcode::V128Eq16 =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(H16, Eq))
    @ir.Opcode::V128Eq32 =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(S32, Eq))
    @ir.Opcode::V128Eq64 =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(D64, Eq))
    @ir.Opcode::V128Ne8 => lower_v128_cmp_ne(ctx, inst, block, B8)
    @ir.Opcode::V128Ne16 => lower_v128_cmp_ne(ctx, inst, block, H16)
    @ir.Opcode::V128Ne32 => lower_v128_cmp_ne(ctx, inst, block, S32)
    @ir.Opcode::V128Ne64 => lower_v128_cmp_ne(ctx, inst, block, D64)
    @ir.Opcode::V128Lt8S => lower_v128_cmp_lt(ctx, inst, block, B8, true)
    @ir.Opcode::V128Lt8U => lower_v128_cmp_lt(ctx, inst, block, B8, false)
    @ir.Opcode::V128Lt16S => lower_v128_cmp_lt(ctx, inst, block, H16, true)
    @ir.Opcode::V128Lt16U => lower_v128_cmp_lt(ctx, inst, block, H16, false)
    @ir.Opcode::V128Lt32S => lower_v128_cmp_lt(ctx, inst, block, S32, true)
    @ir.Opcode::V128Lt32U => lower_v128_cmp_lt(ctx, inst, block, S32, false)
    @ir.Opcode::V128Lt64S => lower_v128_cmp_lt(ctx, inst, block, D64, true)
    @ir.Opcode::V128Gt8S =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(B8, GtS))
    @ir.Opcode::V128Gt8U =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(B8, GtU))
    @ir.Opcode::V128Gt16S =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(H16, GtS))
    @ir.Opcode::V128Gt16U =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(H16, GtU))
    @ir.Opcode::V128Gt32S =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(S32, GtS))
    @ir.Opcode::V128Gt32U =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(S32, GtU))
    @ir.Opcode::V128Gt64S =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(D64, GtS))
    @ir.Opcode::V128Le8S => lower_v128_cmp_le(ctx, inst, block, B8, true)
    @ir.Opcode::V128Le8U => lower_v128_cmp_le(ctx, inst, block, B8, false)
    @ir.Opcode::V128Le16S => lower_v128_cmp_le(ctx, inst, block, H16, true)
    @ir.Opcode::V128Le16U => lower_v128_cmp_le(ctx, inst, block, H16, false)
    @ir.Opcode::V128Le32S => lower_v128_cmp_le(ctx, inst, block, S32, true)
    @ir.Opcode::V128Le32U => lower_v128_cmp_le(ctx, inst, block, S32, false)
    @ir.Opcode::V128Le64S => lower_v128_cmp_le(ctx, inst, block, D64, true)
    @ir.Opcode::V128Ge8S =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(B8, GeS))
    @ir.Opcode::V128Ge8U =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(B8, GeU))
    @ir.Opcode::V128Ge16S =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(H16, GeS))
    @ir.Opcode::V128Ge16U =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(H16, GeU))
    @ir.Opcode::V128Ge32S =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(S32, GeS))
    @ir.Opcode::V128Ge32U =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(S32, GeU))
    @ir.Opcode::V128Ge64S =>
      lower_v128_binary(ctx, inst, block, SIMDCmp(D64, GeS))

    // Narrow/Extend
    @ir.Opcode::V128Narrow16to8S =>
      lower_v128_binary(ctx, inst, block, SIMDNarrow(B8, true))
    @ir.Opcode::V128Narrow16to8U =>
      lower_v128_binary(ctx, inst, block, SIMDNarrow(B8, false))
    @ir.Opcode::V128Narrow32to16S =>
      lower_v128_binary(ctx, inst, block, SIMDNarrow(H16, true))
    @ir.Opcode::V128Narrow32to16U =>
      lower_v128_binary(ctx, inst, block, SIMDNarrow(H16, false))
    @ir.Opcode::V128ExtendLow8to16S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(H16, true))
    @ir.Opcode::V128ExtendHigh8to16S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(H16, true))
    @ir.Opcode::V128ExtendLow8to16U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(H16, false))
    @ir.Opcode::V128ExtendHigh8to16U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(H16, false))
    @ir.Opcode::V128ExtendLow16to32S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(S32, true))
    @ir.Opcode::V128ExtendHigh16to32S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(S32, true))
    @ir.Opcode::V128ExtendLow16to32U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(S32, false))
    @ir.Opcode::V128ExtendHigh16to32U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(S32, false))
    @ir.Opcode::V128ExtendLow32to64S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(D64, true))
    @ir.Opcode::V128ExtendHigh32to64S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(D64, true))
    @ir.Opcode::V128ExtendLow32to64U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(D64, false))
    @ir.Opcode::V128ExtendHigh32to64U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(D64, false))

    // Extended multiply
    @ir.Opcode::V128ExtMulLow8to16S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(H16, true))
    @ir.Opcode::V128ExtMulHigh8to16S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(H16, true))
    @ir.Opcode::V128ExtMulLow8to16U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(H16, false))
    @ir.Opcode::V128ExtMulHigh8to16U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(H16, false))
    @ir.Opcode::V128ExtMulLow16to32S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(S32, true))
    @ir.Opcode::V128ExtMulHigh16to32S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(S32, true))
    @ir.Opcode::V128ExtMulLow16to32U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(S32, false))
    @ir.Opcode::V128ExtMulHigh16to32U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(S32, false))
    @ir.Opcode::V128ExtMulLow32to64S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(D64, true))
    @ir.Opcode::V128ExtMulHigh32to64S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(D64, true))
    @ir.Opcode::V128ExtMulLow32to64U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(D64, false))
    @ir.Opcode::V128ExtMulHigh32to64U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(D64, false))

    // Extended add pairwise
    @ir.Opcode::V128ExtAddPairwise8to16S =>
      lower_v128_unary(ctx, inst, block, SIMDExtAddPairwise(H16, true))
    @ir.Opcode::V128ExtAddPairwise8to16U =>
      lower_v128_unary(ctx, inst, block, SIMDExtAddPairwise(H16, false))
    @ir.Opcode::V128ExtAddPairwise16to32S =>
      lower_v128_unary(ctx, inst, block, SIMDExtAddPairwise(S32, true))
    @ir.Opcode::V128ExtAddPairwise16to32U =>
      lower_v128_unary(ctx, inst, block, SIMDExtAddPairwise(S32, false))

    // Dot product and Q15
    @ir.Opcode::V128Dot16to32S => lower_v128_binary(ctx, inst, block, SIMDDot)
    @ir.Opcode::V128Q15MulrSat16S =>
      lower_v128_binary(ctx, inst, block, SIMDQ15MulrSat)

    // Floating point arithmetic
    @ir.Opcode::V128AddF32 =>
      lower_v128_binary(ctx, inst, block, SIMDFAdd(true))
    @ir.Opcode::V128AddF64 =>
      lower_v128_binary(ctx, inst, block, SIMDFAdd(false))
    @ir.Opcode::V128SubF32 =>
      lower_v128_binary(ctx, inst, block, SIMDFSub(true))
    @ir.Opcode::V128SubF64 =>
      lower_v128_binary(ctx, inst, block, SIMDFSub(false))
    @ir.Opcode::V128MulF32 =>
      lower_v128_binary(ctx, inst, block, SIMDFMul(true))
    @ir.Opcode::V128MulF64 =>
      lower_v128_binary(ctx, inst, block, SIMDFMul(false))
    @ir.Opcode::V128DivF32 =>
      lower_v128_binary(ctx, inst, block, SIMDFDiv(true))
    @ir.Opcode::V128DivF64 =>
      lower_v128_binary(ctx, inst, block, SIMDFDiv(false))
    @ir.Opcode::V128MinF32 =>
      lower_v128_binary(ctx, inst, block, SIMDFMin(true))
    @ir.Opcode::V128MinF64 =>
      lower_v128_binary(ctx, inst, block, SIMDFMin(false))
    @ir.Opcode::V128MaxF32 =>
      lower_v128_binary(ctx, inst, block, SIMDFMax(true))
    @ir.Opcode::V128MaxF64 =>
      lower_v128_binary(ctx, inst, block, SIMDFMax(false))
    @ir.Opcode::V128PMinF32 =>
      lower_v128_binary(ctx, inst, block, SIMDFPMin(true))
    @ir.Opcode::V128PMinF64 =>
      lower_v128_binary(ctx, inst, block, SIMDFPMin(false))
    @ir.Opcode::V128PMaxF32 =>
      lower_v128_binary(ctx, inst, block, SIMDFPMax(true))
    @ir.Opcode::V128PMaxF64 =>
      lower_v128_binary(ctx, inst, block, SIMDFPMax(false))

    // Floating point unary
    @ir.Opcode::V128AbsF32 => lower_v128_unary(ctx, inst, block, SIMDFAbs(true))
    @ir.Opcode::V128AbsF64 =>
      lower_v128_unary(ctx, inst, block, SIMDFAbs(false))
    @ir.Opcode::V128NegF32 => lower_v128_unary(ctx, inst, block, SIMDFNeg(true))
    @ir.Opcode::V128NegF64 =>
      lower_v128_unary(ctx, inst, block, SIMDFNeg(false))
    @ir.Opcode::V128SqrtF32 =>
      lower_v128_unary(ctx, inst, block, SIMDFSqrt(true))
    @ir.Opcode::V128SqrtF64 =>
      lower_v128_unary(ctx, inst, block, SIMDFSqrt(false))
    @ir.Opcode::V128CeilF32 =>
      lower_v128_unary(ctx, inst, block, SIMDFCeil(true))
    @ir.Opcode::V128CeilF64 =>
      lower_v128_unary(ctx, inst, block, SIMDFCeil(false))
    @ir.Opcode::V128FloorF32 =>
      lower_v128_unary(ctx, inst, block, SIMDFFloor(true))
    @ir.Opcode::V128FloorF64 =>
      lower_v128_unary(ctx, inst, block, SIMDFFloor(false))
    @ir.Opcode::V128TruncF32 =>
      lower_v128_unary(ctx, inst, block, SIMDFTrunc(true))
    @ir.Opcode::V128TruncF64 =>
      lower_v128_unary(ctx, inst, block, SIMDFTrunc(false))
    @ir.Opcode::V128NearestF32 =>
      lower_v128_unary(ctx, inst, block, SIMDFNearest(true))
    @ir.Opcode::V128NearestF64 =>
      lower_v128_unary(ctx, inst, block, SIMDFNearest(false))

    // Floating point comparisons
    @ir.Opcode::V128EqF32 =>
      lower_v128_binary(
        ctx,
        inst,
        block,
        SIMDFCmp(true, @instr.SIMDFCmpKind::Eq),
      )
    @ir.Opcode::V128EqF64 =>
      lower_v128_binary(
        ctx,
        inst,
        block,
        SIMDFCmp(false, @instr.SIMDFCmpKind::Eq),
      )
    @ir.Opcode::V128NeF32 => lower_v128_fcmp_ne(ctx, inst, block, true)
    @ir.Opcode::V128NeF64 => lower_v128_fcmp_ne(ctx, inst, block, false)
    @ir.Opcode::V128LtF32 =>
      // lt(a,b) = gt(b,a) - swap operands
      lower_v128_binary_swap(
        ctx,
        inst,
        block,
        SIMDFCmp(true, @instr.SIMDFCmpKind::Gt),
      )
    @ir.Opcode::V128LtF64 =>
      lower_v128_binary_swap(
        ctx,
        inst,
        block,
        SIMDFCmp(false, @instr.SIMDFCmpKind::Gt),
      )
    @ir.Opcode::V128GtF32 =>
      lower_v128_binary(
        ctx,
        inst,
        block,
        SIMDFCmp(true, @instr.SIMDFCmpKind::Gt),
      )
    @ir.Opcode::V128GtF64 =>
      lower_v128_binary(
        ctx,
        inst,
        block,
        SIMDFCmp(false, @instr.SIMDFCmpKind::Gt),
      )
    @ir.Opcode::V128LeF32 =>
      // le(a,b) = ge(b,a) - swap operands
      lower_v128_binary_swap(
        ctx,
        inst,
        block,
        SIMDFCmp(true, @instr.SIMDFCmpKind::Ge),
      )
    @ir.Opcode::V128LeF64 =>
      lower_v128_binary_swap(
        ctx,
        inst,
        block,
        SIMDFCmp(false, @instr.SIMDFCmpKind::Ge),
      )
    @ir.Opcode::V128GeF32 =>
      lower_v128_binary(
        ctx,
        inst,
        block,
        SIMDFCmp(true, @instr.SIMDFCmpKind::Ge),
      )
    @ir.Opcode::V128GeF64 =>
      lower_v128_binary(
        ctx,
        inst,
        block,
        SIMDFCmp(false, @instr.SIMDFCmpKind::Ge),
      )

    // Conversions
    @ir.Opcode::V128TruncSatF32toI32S =>
      lower_v128_unary(ctx, inst, block, SIMDFCvtToIntS(true))
    @ir.Opcode::V128TruncSatF32toI32U =>
      lower_v128_unary(ctx, inst, block, SIMDFCvtToIntU(true))
    @ir.Opcode::V128TruncSatF64toI32SZero =>
      lower_v128_unary(ctx, inst, block, SIMDTruncSatF64ToI32SZero)
    @ir.Opcode::V128TruncSatF64toI32UZero =>
      lower_v128_unary(ctx, inst, block, SIMDTruncSatF64ToI32UZero)
    @ir.Opcode::V128ConvertI32toF32S =>
      lower_v128_unary(ctx, inst, block, SIMDIntToFloatS(true))
    @ir.Opcode::V128ConvertI32toF32U =>
      lower_v128_unary(ctx, inst, block, SIMDIntToFloatU(true))
    @ir.Opcode::V128ConvertLowI32toF64S =>
      lower_v128_unary(ctx, inst, block, SIMDConvertLowI32ToF64S)
    @ir.Opcode::V128ConvertLowI32toF64U =>
      lower_v128_unary(ctx, inst, block, SIMDConvertLowI32ToF64U)
    @ir.Opcode::V128DemoteF64toF32Zero =>
      lower_v128_unary(ctx, inst, block, SIMDDemoteF64ToF32Zero)
    @ir.Opcode::V128PromoteLowF32toF64 =>
      lower_v128_unary(ctx, inst, block, SIMDPromoteLowF32ToF64)

    // Memory operations
    @ir.Opcode::V128Load8x8S(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 8, true, offset.to_int())
    @ir.Opcode::V128Load8x8U(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 8, false, offset.to_int())
    @ir.Opcode::V128Load16x4S(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 16, true, offset.to_int())
    @ir.Opcode::V128Load16x4U(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 16, false, offset.to_int())
    @ir.Opcode::V128Load32x2S(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 32, true, offset.to_int())
    @ir.Opcode::V128Load32x2U(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 32, false, offset.to_int())
    @ir.Opcode::V128Load8Splat(_, _, offset) =>
      lower_v128_load_splat(ctx, inst, block, B8, offset.to_int())
    @ir.Opcode::V128Load16Splat(_, _, offset) =>
      lower_v128_load_splat(ctx, inst, block, H16, offset.to_int())
    @ir.Opcode::V128Load32Splat(_, _, offset) =>
      lower_v128_load_splat(ctx, inst, block, S32, offset.to_int())
    @ir.Opcode::V128Load64Splat(_, _, offset) =>
      lower_v128_load_splat(ctx, inst, block, D64, offset.to_int())
    @ir.Opcode::V128Load32Zero(_, _, offset) =>
      lower_v128_load_zero(ctx, inst, block, false, offset.to_int())
    @ir.Opcode::V128Load64Zero(_, _, offset) =>
      lower_v128_load_zero(ctx, inst, block, true, offset.to_int())
    @ir.Opcode::V128Load8Lane(_, _, offset, lane) =>
      lower_v128_load_lane(ctx, inst, block, B8, lane, offset.to_int())
    @ir.Opcode::V128Load16Lane(_, _, offset, lane) =>
      lower_v128_load_lane(ctx, inst, block, H16, lane, offset.to_int())
    @ir.Opcode::V128Load32Lane(_, _, offset, lane) =>
      lower_v128_load_lane(ctx, inst, block, S32, lane, offset.to_int())
    @ir.Opcode::V128Load64Lane(_, _, offset, lane) =>
      lower_v128_load_lane(ctx, inst, block, D64, lane, offset.to_int())
    @ir.Opcode::V128Store8Lane(_, _, offset, lane) =>
      lower_v128_store_lane(ctx, inst, block, B8, lane, offset.to_int())
    @ir.Opcode::V128Store16Lane(_, _, offset, lane) =>
      lower_v128_store_lane(ctx, inst, block, H16, lane, offset.to_int())
    @ir.Opcode::V128Store32Lane(_, _, offset, lane) =>
      lower_v128_store_lane(ctx, inst, block, S32, lane, offset.to_int())
    @ir.Opcode::V128Store64Lane(_, _, offset, lane) =>
      lower_v128_store_lane(ctx, inst, block, D64, lane, offset.to_int())

    // ============ Relaxed SIMD ============
    // relaxed_swizzle: same as swizzle (TBL instruction, out-of-range gives 0)
    @ir.Opcode::V128RelaxedSwizzle => lower_v128_swizzle(ctx, inst, block)

    // relaxed_trunc: same as trunc_sat (the relaxation is for NaN behavior)
    @ir.Opcode::V128RelaxedTruncF32toI32S =>
      lower_v128_unary(ctx, inst, block, SIMDFCvtToIntS(true))
    @ir.Opcode::V128RelaxedTruncF32toI32U =>
      lower_v128_unary(ctx, inst, block, SIMDFCvtToIntU(true))
    @ir.Opcode::V128RelaxedTruncF64toI32SZero =>
      lower_v128_unary(ctx, inst, block, SIMDTruncSatF64ToI32SZero)
    @ir.Opcode::V128RelaxedTruncF64toI32UZero =>
      lower_v128_unary(ctx, inst, block, SIMDTruncSatF64ToI32UZero)

    // relaxed_madd/nmadd: fused multiply-add/subtract
    @ir.Opcode::V128RelaxedMaddF32 =>
      lower_v128_fma(ctx, inst, block, true, false)
    @ir.Opcode::V128RelaxedNmaddF32 =>
      lower_v128_fma(ctx, inst, block, true, true)
    @ir.Opcode::V128RelaxedMaddF64 =>
      lower_v128_fma(ctx, inst, block, false, false)
    @ir.Opcode::V128RelaxedNmaddF64 =>
      lower_v128_fma(ctx, inst, block, false, true)

    // relaxed_laneselect: same as bitselect (BSL instruction)
    @ir.Opcode::V128RelaxedLaneselect8 =>
      lower_v128_ternary(ctx, inst, block, SIMDBsl)
    @ir.Opcode::V128RelaxedLaneselect16 =>
      lower_v128_ternary(ctx, inst, block, SIMDBsl)
    @ir.Opcode::V128RelaxedLaneselect32 =>
      lower_v128_ternary(ctx, inst, block, SIMDBsl)
    @ir.Opcode::V128RelaxedLaneselect64 =>
      lower_v128_ternary(ctx, inst, block, SIMDBsl)

    // relaxed_min/max: use FMIN/FMAX (relaxation is for NaN propagation)
    @ir.Opcode::V128RelaxedMinF32 =>
      lower_v128_binary(ctx, inst, block, SIMDFMin(true))
    @ir.Opcode::V128RelaxedMaxF32 =>
      lower_v128_binary(ctx, inst, block, SIMDFMax(true))
    @ir.Opcode::V128RelaxedMinF64 =>
      lower_v128_binary(ctx, inst, block, SIMDFMin(false))
    @ir.Opcode::V128RelaxedMaxF64 =>
      lower_v128_binary(ctx, inst, block, SIMDFMax(false))

    // relaxed_q15mulr_s: same as q15mulr_s (SQRDMULH instruction)
    @ir.Opcode::V128RelaxedQ15MulrS =>
      lower_v128_binary(ctx, inst, block, SIMDQ15MulrSat)

    // relaxed_dot products
    @ir.Opcode::V128RelaxedDot8to16S =>
      lower_v128_binary(ctx, inst, block, SIMDRelaxedDot8to16)
    @ir.Opcode::V128RelaxedDot8to32AddS =>
      lower_v128_relaxed_dot_add(ctx, inst, block)
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
  if inst.first_result() is Some(result) {
    // Skip if this Icmp will be fused with a Select (to avoid redundant Cmp)
    if ctx.fused_icmps.contains(result.id) {
      return
    }
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
  if inst.first_result() is Some(result) {
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

      // Lower SSA block arguments directly onto the terminator.
      // The target block's params are created during lower_function; we rely on
      // bundle merging to coalesce param vregs with their incoming args.
      let regs : Array[@abi.Reg] = []
      for a in args {
        regs.push(Virtual(ctx.get_vreg_for_use(a, block)))
      }
      block.set_terminator(Jump(target_id, regs))
    }
    @ir.Terminator::Brz(cond, then_block, else_block) => {
      let then_id = ctx.get_block_id(then_block)
      let else_id = ctx.get_block_id(else_block)
      // brz means branch if zero, so:
      // - If condition is from icmp, invert the condition for BranchCmp/BranchCmpImm
      // - Otherwise use BranchZero with is_nonzero=false
      if match_icmp_value(ctx, cond) is Some((lhs, rhs, cc)) {
        // Brz(icmp(cc, a, b)) = branch to then if icmp result is 0 (i.e., condition is false)
        // So we need to branch to else_block if condition is true, then_block if false
        // This means: BranchCmp with swapped targets
        let vcode_cond = intcc_to_cond(cc)
        // Determine is_64 from operand type (same as lower_icmp)
        let is_64 = match lhs.ty {
          @ir.Type::I64 | @ir.Type::FuncRef | @ir.Type::ExternRef => true
          _ => false
        }
        // Try to use BranchCmpImm if RHS is a valid immediate
        if match_add_imm_value(ctx, rhs) is Some(imm) {
          let lhs_vreg = ctx.get_vreg_for_use(lhs, block)
          // Note: swapped - branch to else_id if condition is true
          block.set_terminator(
            BranchCmpImm(
              Virtual(lhs_vreg),
              imm.to_int(),
              vcode_cond,
              is_64,
              else_id,
              then_id,
            ),
          )
        } else {
          let lhs_vreg = ctx.get_vreg_for_use(lhs, block)
          let rhs_vreg = ctx.get_vreg_for_use(rhs, block)
          // Note: swapped - branch to else_id if condition is true
          block.set_terminator(
            BranchCmp(
              Virtual(lhs_vreg),
              Virtual(rhs_vreg),
              vcode_cond,
              is_64,
              else_id,
              then_id,
            ),
          )
        }
      } else {
        // Use BranchZero: branch to then_block if reg is zero
        // Condition result is always i32, so is_64=false
        let cond_vreg = ctx.get_vreg_for_use(cond, block)
        block.set_terminator(
          BranchZero(Virtual(cond_vreg), false, false, then_id, else_id),
        )
      }
    }
    @ir.Terminator::Brnz(cond, then_block, else_block) => {
      let then_id = ctx.get_block_id(then_block)
      let else_id = ctx.get_block_id(else_block)
      // brnz means branch if nonzero, so:
      // - If condition is from icmp, use BranchCmp/BranchCmpImm directly
      // - Otherwise use BranchZero with is_nonzero=true
      if match_icmp_value(ctx, cond) is Some((lhs, rhs, cc)) {
        // Brnz(icmp(cc, a, b)) = branch to then if icmp result is nonzero (i.e., condition is true)
        let vcode_cond = intcc_to_cond(cc)
        // Determine is_64 from operand type (same as lower_icmp)
        let is_64 = match lhs.ty {
          @ir.Type::I64 | @ir.Type::FuncRef | @ir.Type::ExternRef => true
          _ => false
        }
        // Try to use BranchCmpImm if RHS is a valid immediate
        if match_add_imm_value(ctx, rhs) is Some(imm) {
          let lhs_vreg = ctx.get_vreg_for_use(lhs, block)
          block.set_terminator(
            BranchCmpImm(
              Virtual(lhs_vreg),
              imm.to_int(),
              vcode_cond,
              is_64,
              then_id,
              else_id,
            ),
          )
        } else {
          let lhs_vreg = ctx.get_vreg_for_use(lhs, block)
          let rhs_vreg = ctx.get_vreg_for_use(rhs, block)
          block.set_terminator(
            BranchCmp(
              Virtual(lhs_vreg),
              Virtual(rhs_vreg),
              vcode_cond,
              is_64,
              then_id,
              else_id,
            ),
          )
        }
      } else {
        // Use BranchZero: branch to then_block if reg is nonzero
        // Condition result is always i32, so is_64=false
        let cond_vreg = ctx.get_vreg_for_use(cond, block)
        block.set_terminator(
          BranchZero(Virtual(cond_vreg), true, false, then_id, else_id),
        )
      }
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
        block.set_terminator(Jump(default_id, []))
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
  // Collect argument vregs, rematerializing single-use constants only for
  // direct calls. Indirect calls (imports or default path) keep original vregs.
  let use_const_args = ctx.num_imports >= 0 && func_idx >= ctx.num_imports
  let (arg_vregs, const_args) = if use_const_args {
    collect_call_args_with_consts(ctx, inst.operands, block, 0)
  } else {
    let args : Array[@abi.VReg] = []
    for operand in inst.operands {
      args.push(ctx.get_vreg_for_use(operand, block))
    }
    (args, {})
  }

  // Collect result vregs (skip when results are unused)
  let result_vregs = collect_call_result_vregs(ctx, inst)
  if ctx.num_imports < 0 || func_idx < ctx.num_imports {
    // Imports: load function pointer from vmctx func_table and call indirectly.
    let func_table = emit_load_func_table(ctx, block)
    let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
    let offset = func_idx * 8
    let load_inst = @instr.VCodeInst::new(Load(I64, offset))
    load_inst.add_def({ reg: Virtual(func_ptr_vreg) })
    load_inst.add_use(Virtual(func_table))
    block.add_inst(load_inst)
    lower_wasm_call(
      ctx, block, func_ptr_vreg, arg_vregs, result_vregs, const_args,
    )
  } else {
    // Internal functions: direct call.
    lower_wasm_call_direct(
      ctx, block, func_idx, arg_vregs, result_vregs, const_args,
    )
  }
}

// NOTE: lower_global_get, lower_global_set are removed
// These operations are desugared via FuncEnvironment at IR level to LoadPtr/StorePtr

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
  guard inst.first_result() is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Convert IR type to VCode memory type and get access size
  let mem_ty = ir_type_to_mem_type(ty)
  let access_size = match ty {
    @ir.Type::I32 | @ir.Type::F32 => 4
    @ir.Type::I64 | @ir.Type::F64 | @ir.Type::FuncRef | @ir.Type::ExternRef => 8
    @ir.Type::V128 => 16
  }

  // Get the base pointer and offset from operands
  // operand 0 = base pointer
  // operand 1 = offset constant (optional)
  let base_value = inst.operands[0]

  // Check if we have an offset from a second operand (must be an iconst)
  let explicit_offset = if inst.operands.length() > 1 {
    if find_defining_inst(ctx, inst.operands[1]) is Some(def_inst) &&
      def_inst.opcode is @ir.Opcode::Iconst(off) {
      off
    } else {
      0L
    }
  } else {
    0L
  }

  // Try to fold address calculation: if base is iadd(real_base, const),
  // we can fold the const into the load offset
  let (actual_base_value, total_offset) = if match_iadd_const(ctx, base_value)
    is Some((real_base, addr_offset)) {
    let combined = explicit_offset + addr_offset
    if is_valid_load_store_offset(combined, access_size) {
      (real_base, combined.to_int())
    } else {
      // Offset too large or unaligned, can't fold
      (base_value, explicit_offset.to_int())
    }
  } else {
    (base_value, explicit_offset.to_int())
  }
  let base = ctx.get_vreg_for_use(actual_base_value, block)

  // Create LoadPtr instruction
  let load_inst = @instr.VCodeInst::new(LoadPtr(mem_ty, total_offset))
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

  // Convert IR type to VCode memory type and get access size
  let mem_ty = ir_type_to_mem_type(ty)
  let access_size = match ty {
    @ir.Type::I32 | @ir.Type::F32 => 4
    @ir.Type::I64 | @ir.Type::F64 | @ir.Type::FuncRef | @ir.Type::ExternRef => 8
    @ir.Type::V128 => 16
  }
  let base_value = inst.operands[0]
  let store_value = inst.operands[1]

  // Check if we have an offset from a third operand
  let explicit_offset = if inst.operands.length() > 2 {
    if find_defining_inst(ctx, inst.operands[2]) is Some(def_inst) &&
      def_inst.opcode is @ir.Opcode::Iconst(off) {
      off
    } else {
      0L
    }
  } else {
    0L
  }

  // Try to fold address calculation: if base is iadd(real_base, const),
  // we can fold the const into the store offset
  let (actual_base_value, total_offset) = if match_iadd_const(ctx, base_value)
    is Some((real_base, addr_offset)) {
    let combined = explicit_offset + addr_offset
    if is_valid_load_store_offset(combined, access_size) {
      (real_base, combined.to_int())
    } else {
      // Offset too large or unaligned, can't fold
      (base_value, explicit_offset.to_int())
    }
  } else {
    (base_value, explicit_offset.to_int())
  }
  let base = ctx.get_vreg_for_use(actual_base_value, block)
  let value = ctx.get_vreg_for_use(store_value, block)

  // Create StorePtr instruction
  let store_inst = @instr.VCodeInst::new(StorePtr(mem_ty, total_offset))
  store_inst.add_use(Virtual(base))
  store_inst.add_use(Virtual(value))
  block.add_inst(store_inst)
}

///|
/// Lower load_ptr_narrow instruction (raw pointer narrow load without bounds checking)
/// Used by FuncEnvironment for memory loads
fn lower_load_ptr_narrow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  _result_ty : @ir.Type,
  bits : Int,
  signed : Bool,
) -> Unit {
  // operand 0 = base pointer
  // operand 1 = offset constant
  guard inst.operands.length() >= 1 else { return }
  guard inst.first_result() is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Access size in bytes
  let access_size = bits / 8
  let base_value = inst.operands[0]

  // Check if we have an offset from a second operand
  let explicit_offset = if inst.operands.length() > 1 {
    if find_defining_inst(ctx, inst.operands[1]) is Some(def_inst) &&
      def_inst.opcode is @ir.Opcode::Iconst(off) {
      off
    } else {
      0L
    }
  } else {
    0L
  }

  // Try to fold address calculation: if base is iadd(real_base, const),
  // we can fold the const into the load offset
  let (actual_base_value, total_offset) = if match_iadd_const(ctx, base_value)
    is Some((real_base, addr_offset)) {
    let combined = explicit_offset + addr_offset
    if is_valid_load_store_offset(combined, access_size) {
      (real_base, combined.to_int())
    } else {
      (base_value, explicit_offset.to_int())
    }
  } else {
    (base_value, explicit_offset.to_int())
  }
  let base = ctx.get_vreg_for_use(actual_base_value, block)

  // Create LoadPtrNarrow instruction
  let load_inst = @instr.VCodeInst::new(
    LoadPtrNarrow(bits, signed, total_offset),
  )
  load_inst.add_def({ reg: Virtual(result_vreg) })
  load_inst.add_use(Virtual(base))
  block.add_inst(load_inst)
}

///|
/// Lower store_ptr_narrow instruction (raw pointer narrow store without bounds checking)
/// Used by FuncEnvironment for memory stores
fn lower_store_ptr_narrow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  bits : Int,
) -> Unit {
  // operand 0 = base pointer
  // operand 1 = value to store
  // operand 2 = offset constant (optional)
  guard inst.operands.length() >= 2 else { return }

  // Access size in bytes
  let access_size = bits / 8
  let base_value = inst.operands[0]
  let store_value = inst.operands[1]

  // Check if we have an offset from a third operand
  let explicit_offset = if inst.operands.length() > 2 {
    if find_defining_inst(ctx, inst.operands[2]) is Some(def_inst) &&
      def_inst.opcode is @ir.Opcode::Iconst(off) {
      off
    } else {
      0L
    }
  } else {
    0L
  }

  // Try to fold address calculation: if base is iadd(real_base, const),
  // we can fold the const into the store offset
  let (actual_base_value, total_offset) = if match_iadd_const(ctx, base_value)
    is Some((real_base, addr_offset)) {
    let combined = explicit_offset + addr_offset
    if is_valid_load_store_offset(combined, access_size) {
      (real_base, combined.to_int())
    } else {
      (base_value, explicit_offset.to_int())
    }
  } else {
    (base_value, explicit_offset.to_int())
  }
  let base = ctx.get_vreg_for_use(actual_base_value, block)
  let value = ctx.get_vreg_for_use(store_value, block)

  // Create StorePtrNarrow instruction
  let store_inst = @instr.VCodeInst::new(StorePtrNarrow(bits, total_offset))
  store_inst.add_use(Virtual(base))
  store_inst.add_use(Virtual(value))
  block.add_inst(store_inst)
}
