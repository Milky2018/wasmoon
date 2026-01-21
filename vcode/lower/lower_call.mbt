// ============ Wasm Call Lowering (Standard) ============

///|
/// Call argument constant that can be rematerialized at the callsite.
priv enum CallConstArg {
  Int(Int64)
  F32(Int)
  F64(Int64)
}

///|
/// Emit a constant load for a call argument, optionally constrained to a register.
fn emit_call_const(
  block : @block.VCodeBlock,
  vreg : @abi.VReg,
  value : CallConstArg,
  preg? : @abi.PReg? = None,
) -> Unit {
  let opcode = match value {
    Int(v) => @instr.LoadConst(v)
    F32(bits) => @instr.LoadConstF32(bits)
    F64(bits) => @instr.LoadConstF64(bits)
  }
  let inst = @instr.VCodeInst::new(opcode)
  match preg {
    Some(p) => inst.add_def_fixed({ reg: Virtual(vreg) }, p)
    None => inst.add_def({ reg: Virtual(vreg) })
  }
  block.add_inst(inst)
}

///|
/// Emit StoreToStack for overflow arguments according to the Wasm ABI.
/// This also updates `max_outgoing_args_size` so the prologue reserves enough
/// space and SP doesn't move at call sites.
fn emit_wasm_overflow_arg_stores(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  int_args : Array[(@abi.VReg, @abi.RegClass)],
  float_args : Array[(@abi.VReg, @abi.RegClass)],
) -> Unit {
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS // 7 (X1-X7)
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS // 8 (V0-V7)
  let int_overflow = if int_args.length() > max_int_reg_args {
    int_args.length() - max_int_reg_args
  } else {
    0
  }
  let float_overflow_classes : Array[@abi.RegClass] = []
  for i in max_float_reg_args..<float_args.length() {
    let (_, class) = float_args[i]
    float_overflow_classes.push(class)
  }
  let (int_offsets, float_offsets, total_bytes) = @abi.wasm_layout_overflow_stack(
    int_overflow, float_overflow_classes,
  )
  if total_bytes > 0 {
    ctx.vcode_func.update_max_outgoing_args_size(total_bytes)
  }
  for i in 0..<int_overflow {
    let (vreg, _) = int_args[max_int_reg_args + i]
    let store = @instr.VCodeInst::new(StoreToStack(int_offsets[i]))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }
  for i in 0..<float_offsets.length() {
    let (vreg, _) = float_args[max_float_reg_args + i]
    let store = @instr.VCodeInst::new(StoreToStack(float_offsets[i]))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }
}

///|
/// Lower a Wasm call with a prebuilt call instruction.
fn lower_wasm_call_common(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  call_inst : @instr.VCodeInst,
  args : Array[@abi.VReg],
  results : Array[@abi.VReg],
  const_args : Map[Int, CallConstArg],
) -> Unit {
  if !ctx.abi_settings.enable_pinned_reg {
    abort("unpinned VMContext ABI not implemented yet")
  }
  // vmctx is pinned in `REG_VMCTX` (X21 when pinned).
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }

  // Classify user arguments by type
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for arg in args {
    match arg.class {
      @abi.Int => int_args.push((arg, @abi.Int))
      @abi.Float32 => float_args.push((arg, @abi.Float32))
      @abi.Float64 => float_args.push((arg, @abi.Float64))
      @abi.Vector => float_args.push((arg, @abi.Vector)) // SIMD uses Vn registers
    }
  }

  // Materialize constant overflow args before storing to stack.
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS
  for i in max_int_reg_args..<int_args.length() {
    let (vreg, _) = int_args[i]
    if const_args.get(vreg.id) is Some(value) {
      emit_call_const(block, vreg, value)
    }
  }
  for i in max_float_reg_args..<float_args.length() {
    let (vreg, _) = float_args[i]
    if const_args.get(vreg.id) is Some(value) {
      emit_call_const(block, vreg, value)
    }
  }

  // Store overflow args to stack (pre-allocated outgoing args area at SP).
  emit_wasm_overflow_arg_stores(ctx, block, int_args, float_args)

  // vmctx constrained to X0.
  let vmctx_arg_preg : @abi.PReg = {
    index: @abi.REG_CALLEE_VMCTX,
    class: @abi.Int,
  }
  call_inst.add_use_fixed(Physical(vmctx_preg), vmctx_arg_preg)

  // Register int args: X1-X7
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg_idx = @abi.USER_PARAM_BASE_REG + i
    let preg = @abi.PReg::{ index: preg_idx, class: @abi.Int }
    if const_args.get(vreg.id) is Some(value) {
      emit_call_const(block, vreg, value)
    }
    call_inst.add_use_fixed(Virtual(vreg), preg)
  }

  // Register float args: V0-V7
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, arg_class) = float_args[i]
    let preg = @abi.PReg::{ index: i, class: arg_class }
    if const_args.get(vreg.id) is Some(value) {
      emit_call_const(block, vreg, value)
    }
    // For float registers V0-V7:
    // - f32 uses Float32 class (S registers)
    // - f64 uses Float64 class (D registers)
    // - V128 uses Vector class (Q registers)
    // All map to the same underlying Vn registers, but class affects move size
    call_inst.add_use_fixed(Virtual(vreg), preg)
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
      @abi.Float32 | @abi.Float64 | @abi.Vector => {
        // Float/Vector results go to V0, V1, ...
        // Use actual class for proper move size (32/64/128 bits)
        call_inst.add_def_fixed({ reg: Virtual(result) }, @abi.PReg::{
          index: float_result_idx,
          class: result.class,
        })
        float_result_idx += 1
      }
    }
  }

  // Add clobbers for all caller-saved registers
  add_call_clobbers(call_inst)
  block.add_inst(call_inst)
}

///|
/// Lower a Wasm function call using Standard approach.
/// All argument placement is done in lowering via FixedReg constraints.
/// The emit phase just emits BLR to the call target register.
///
/// Wasm ABI (Cranelift-style):
/// - X0 = vmctx
/// - X1-X7 = integer user args (up to 7)
/// - V0-V7 = float user args (up to 8)
/// - Overflow args go to stack
/// - X0/V0 = first result, etc.
fn lower_wasm_call(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  func_ptr : @abi.VReg,
  args : Array[@abi.VReg],
  results : Array[@abi.VReg],
  const_args : Map[Int, CallConstArg],
) -> Unit {
  let num_args = args.length()
  let num_results = results.length()
  let call_inst = @instr.VCodeInst::new(CallPtr(num_args, num_results, Wasm))
  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr), @abi.PReg::{
    index: @abi.SCRATCH_REG_2,
    class: @abi.Int,
  })
  lower_wasm_call_common(ctx, block, call_inst, args, results, const_args)
}

///|
/// Lower a direct Wasm function call.
fn lower_wasm_call_direct(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  func_idx : Int,
  args : Array[@abi.VReg],
  results : Array[@abi.VReg],
  const_args : Map[Int, CallConstArg],
) -> Unit {
  let num_args = args.length()
  let num_results = results.length()
  let call_inst = @instr.VCodeInst::new(
    CallDirect(func_idx, num_args, num_results, Wasm),
  )
  lower_wasm_call_common(ctx, block, call_inst, args, results, const_args)
}

// ============ Tail Call Lowering (Standard) ============

///|
/// Lower direct return_call (tail call optimization)
/// Note: parameters are handled in lowering phase
/// - Overflow args: StoreToStack instructions
/// - Register args: Fixed register constraints via add_use_fixed
/// - ReturnCallIndirect instruction only contains func_ptr use
fn lower_return_call(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  func_idx : Int,
) -> Unit {
  // Load function address (patched at JIT module load time)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(LoadFuncAddr(func_idx))
  load_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_inst)

  // Get pinned vmctx.
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
      @abi.Vector => float_args.push((vreg, @abi.Vector)) // SIMD uses Vn registers
    }
  }

  // Calculate overflow args count (user args, not including vmctx)
  emit_wasm_overflow_arg_stores(ctx, block, int_args, float_args)

  // Create ReturnCallIndirect instruction with fixed register constraints
  let call_inst = @instr.VCodeInst::new(ReturnCallIndirect(0, 0))

  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr_vreg), @abi.PReg::{
    index: @abi.SCRATCH_REG_2,
    class: @abi.Int,
  })

  // vmctx constrained to X0
  call_inst.add_use_fixed(Physical(vmctx_preg), @abi.PReg::{
    index: 0,
    class: @abi.Int,
  })

  // Register int args: X1-X7
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg_idx = @abi.USER_PARAM_BASE_REG + i
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{
      index: preg_idx,
      class: @abi.Int,
    })
  }

  // Register float args: V0-V7
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS
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
/// Note: parameters handled in lowering via StoreToStack and add_use_fixed
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
    load_array_inst.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
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

  // Type check via libcall (supports GC subtyping and structural equivalence)
  // gc_type_check_subtype(actual_type, expected_type) - traps if not a subtype
  let check_func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_check_ptr = @instr.VCodeInst::new(LoadGCFuncPtr(TypeCheckSubtype))
  load_check_ptr.add_def({ reg: Virtual(check_func_ptr_vreg) })
  block.add_inst(load_check_ptr)
  let expected_type_vreg = materialize_imm(ctx, block, type_idx.to_int64())
  lower_c_libcall(
    ctx,
    block,
    check_func_ptr_vreg,
    [actual_type_vreg, expected_type_vreg],
    None,
  )

  // Get pinned vmctx.
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
      @abi.Vector => float_args.push((vreg, @abi.Vector)) // SIMD uses Vn registers
    }
  }
  emit_wasm_overflow_arg_stores(ctx, block, int_args, float_args)

  // Create ReturnCallIndirect with fixed constraints
  let call_inst = @instr.VCodeInst::new(ReturnCallIndirect(0, 0))

  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr_vreg), @abi.PReg::{
    index: @abi.SCRATCH_REG_2,
    class: @abi.Int,
  })

  // vmctx -> X0
  call_inst.add_use_fixed(Physical(vmctx_preg), @abi.PReg::{
    index: 0,
    class: @abi.Int,
  })

  // Register int args: X1-X7
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg_idx = @abi.USER_PARAM_BASE_REG + i
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{
      index: preg_idx,
      class: @abi.Int,
    })
  }

  // Register float args: V0-V7
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS
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
/// Note: parameters handled in lowering
fn lower_return_call_ref(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  _type_idx : Int,
) -> Unit {
  guard inst.operands.length() > 0 else { return }
  let func_ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Strip FUNCREF_TAG (0x2000000000000000) to get raw function pointer
  // func_ptr = func_ref & 0xDFFFFFFFFFFFFFFF (clear bit 61)
  let mask_vreg = ctx.vcode_func.new_vreg(Int)
  let load_mask = @instr.VCodeInst::new(LoadConst(0xDFFFFFFFFFFFFFFFL))
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
      @abi.Vector => float_args.push((vreg, @abi.Vector)) // SIMD uses Vn registers
    }
  }
  emit_wasm_overflow_arg_stores(ctx, block, int_args, float_args)

  // Create ReturnCallIndirect with fixed constraints
  let call_inst = @instr.VCodeInst::new(ReturnCallIndirect(0, 0))

  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr_vreg), @abi.PReg::{
    index: @abi.SCRATCH_REG_2,
    class: @abi.Int,
  })

  // vmctx -> X0
  call_inst.add_use_fixed(Physical(vmctx_preg), @abi.PReg::{
    index: 0,
    class: @abi.Int,
  })

  // Register int args: X1-X7
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg_idx = @abi.USER_PARAM_BASE_REG + i
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{
      index: preg_idx,
      class: @abi.Int,
    })
  }

  // Register float args: V0-V7
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS
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
  // on-demand (no pre-loaded registers for table pointers)
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
    load_array_inst.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
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
  let const_args : Map[Int, CallConstArg] = {}

  // Collect result vregs (skip when results are unused)
  let result_vregs = collect_call_result_vregs(ctx, inst)

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
  // table_ptr is loaded on-demand from vmctx (on-demand)
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

  // Step 5: Type check via libcall (supports subtyping for GC proposal)
  // gc_type_check_subtype(actual_type, expected_type) - traps if not a subtype
  let check_func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_check_ptr = @instr.VCodeInst::new(LoadGCFuncPtr(TypeCheckSubtype))
  load_check_ptr.add_def({ reg: Virtual(check_func_ptr_vreg) })
  block.add_inst(load_check_ptr)
  let expected_type_vreg = materialize_imm(
    ctx,
    block,
    expected_type_idx.to_int64(),
  )
  lower_c_libcall(
    ctx,
    block,
    check_func_ptr_vreg,
    [actual_type_vreg, expected_type_vreg],
    None,
  )

  // Step 6: Use Standard call lowering
  lower_wasm_call(
    ctx, block, func_ptr_vreg, arg_vregs, result_vregs, const_args,
  )
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
  let const_args : Map[Int, CallConstArg] = {}

  // Collect result vregs (skip when results are unused)
  let result_vregs = collect_call_result_vregs(ctx, inst)

  // Step 1: Strip FUNCREF_TAG (0x2000000000000000) to get raw function pointer
  // func_ptr = func_ref & 0xDFFFFFFFFFFFFFFF (clear bit 61)
  let mask_vreg = ctx.vcode_func.new_vreg(Int)
  let load_mask = @instr.VCodeInst::new(LoadConst(0xDFFFFFFFFFFFFFFFL))
  load_mask.add_def({ reg: Virtual(mask_vreg) })
  block.add_inst(load_mask)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let and_inst = @instr.VCodeInst::new(And)
  and_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  and_inst.add_use(Virtual(func_ref_vreg))
  and_inst.add_use(Virtual(mask_vreg))
  block.add_inst(and_inst)

  // Step 2: Use Standard call lowering
  lower_wasm_call(
    ctx, block, func_ptr_vreg, arg_vregs, result_vregs, const_args,
  )
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
  // Add clobbers for caller-saved FPRs.
  //
  // Cranelift-style conservative clobbers (V0-V31) apply to C calls.
  // For Wasm-to-Wasm calls (same ABI), we treat V8-V15 as callee-saved.
  let fpr_clobbers = match call_inst.opcode {
    CallPtr(_, _, @instr.C) => @abi.call_clobbered_fprs()
    _ => @abi.call_clobbered_fprs_same_abi()
  }
  for preg in fpr_clobbers {
    call_inst.add_def({ reg: Physical(preg) })
  }
}

///|
/// Lower call_ptr instruction (call through a function pointer)
/// Used in trampolines to call the target WASM function
///
/// Operand layout:
///   operand 0 = function pointer
///   operand 1 = vmctx (X0)
///   operands 2..n = user arguments
///
/// Standard ABI refactoring:
/// - Stack args are handled in lower phase via StoreToStack instructions
/// - Register args use FixedReg constraints to tell regalloc which physical registers to use
/// - Call target is constrained to SCRATCH_REG_2 (IP1)
fn lower_call_ptr(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  num_args : Int,
  _num_results : Int,
) -> Unit {
  // Collect function pointer
  let func_ptr = ctx.get_vreg_for_use(inst.operands[0], block)

  // Collect vmctx argument
  let callee_vmctx = ctx.get_vreg_for_use(inst.operands[1], block)

  // Classify user arguments by type (starting from operand index 2)
  // int_args and float_args contain (vreg, class) tuples
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for i in 2..<inst.operands.length() {
    let vreg = ctx.get_vreg_for_use(inst.operands[i], block)
    match vreg.class {
      @abi.Int => int_args.push((vreg, @abi.Int))
      @abi.Float32 => float_args.push((vreg, @abi.Float32))
      @abi.Float64 => float_args.push((vreg, @abi.Float64))
      @abi.Vector => float_args.push((vreg, @abi.Vector)) // SIMD uses Vn registers
    }
  }
  emit_wasm_overflow_arg_stores(ctx, block, int_args, float_args)

  // Collect result vregs (skip when results are unused)
  let result_vregs = collect_call_result_vregs(ctx, inst)

  // Step 3: Create CallPtr instruction with FixedReg constraints (Wasm calling convention)
  let call_inst = @instr.VCodeInst::new(
    CallPtr(num_args, result_vregs.length(), Wasm),
  )

  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr), @abi.PReg::{
    index: @abi.SCRATCH_REG_2,
    class: @abi.Int,
  })

  // callee_vmctx constrained to X0
  call_inst.add_use_fixed(Virtual(callee_vmctx), @abi.PReg::{
    index: 0,
    class: @abi.Int,
  })

  // Register int args: X1-X7
  let max_int_reg_args = @abi.MAX_USER_REG_PARAMS
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg_idx = @abi.USER_PARAM_BASE_REG + i
    call_inst.add_use_fixed(Virtual(vreg), @abi.PReg::{
      index: preg_idx,
      class: @abi.Int,
    })
  }

  // Register float args: V0-V7
  let max_float_reg_args = @abi.MAX_FLOAT_REG_PARAMS
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
  let mut int_result_idx = 0
  let mut float_result_idx = 0
  for dst in result_vregs {
    match dst.class {
      @abi.Int => {
        // Integer results go to X0, X1, ...
        call_inst.add_def_fixed({ reg: Virtual(dst) }, @abi.PReg::{
          index: int_result_idx,
          class: @abi.Int,
        })
        int_result_idx = int_result_idx + 1
      }
      @abi.Float32 | @abi.Float64 | @abi.Vector => {
        // Float/Vector results go to V0, V1, ...
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

// ============ C Libcall Lowering (Standard) ============

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

  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr), @abi.PReg::{
    index: @abi.SCRATCH_REG_2,
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
