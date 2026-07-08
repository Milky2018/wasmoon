// ============ Wasm Call Lowering (Standard) ============

///|
/// Call argument constant that can be rematerialized at the callsite.
priv enum CallConstArg {
  Int(Int64)
  F32(Int)
  F64(Int64)
}

///|
fn wasm_func_symbol(func_idx : Int) -> @instr.CodeSymbol {
  @instr.CodeSymbol::new("wasm.func", func_idx)
}

///|
fn emit_exact_indirect_type_check(
  ctx : @lower.LoweringContext,
  block : @block.MachVBlock,
  actual_type_vreg : @abi.VReg,
  expected_type_idx : Int,
) -> Unit {
  let expected_type_vreg = ctx.machv_function().new_vreg(Int)
  let load_expected = @instr.MachVInst::new(
    LoadConst(expected_type_idx.to_int64()),
  )
  load_expected.add_def({ reg: Virtual(expected_type_vreg) })
  block.add_inst(load_expected)

  let cmp = @instr.MachVInst::new(IntCmp(false))
  cmp.add_use(Virtual(actual_type_vreg))
  cmp.add_use(Virtual(expected_type_vreg))
  block.add_inst(cmp)

  let trap = @instr.MachVInst::new(TrapIf(Ne, 2))
  block.add_inst(trap)
}

///|
/// Emit a constant load for a call argument, optionally constrained to a register.
fn emit_call_const(
  block : @block.MachVBlock,
  vreg : @abi.VReg,
  value : CallConstArg,
  preg? : @abi.PReg? = None,
) -> Unit {
  let opcode = match value {
    Int(v) => @instr.LoadConst(v)
    F32(bits) => LoadConstF32(bits)
    F64(bits) => LoadConstF64(bits)
  }
  let inst = @instr.MachVInst::new(opcode)
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
  ctx : @lower.LoweringContext,
  block : @block.MachVBlock,
  int_args : Array[(@abi.VReg, @abi.RegClass)],
  float_args : Array[(@abi.VReg, @abi.RegClass)],
) -> Int {
  let call_conv = ctx.call_conv_layout()
  let max_int_reg_args = call_conv.user_arg_gprs.length()
  let max_float_reg_args = call_conv.arg_fprs.length()
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
  let (int_offsets, float_offsets, total_bytes) = call_conv.layout_overflow_stack(
    int_overflow, float_overflow_classes,
  )
  if total_bytes > 0 {
    ctx.machv_function().update_max_outgoing_args_size(total_bytes)
  }
  for i in 0..<int_overflow {
    let (vreg, _) = int_args[max_int_reg_args + i]
    let store = @instr.MachVInst::new(StoreToStack(int_offsets[i]))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }
  for i in 0..<float_offsets.length() {
    let (vreg, _) = float_args[max_float_reg_args + i]
    let store = @instr.MachVInst::new(StoreToStack(float_offsets[i]))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }
  total_bytes
}

///|
/// Lower a Wasm call with a prebuilt call instruction.
fn lower_wasm_call_common(
  ctx : @lower.LoweringContext,
  block : @block.MachVBlock,
  call_inst : @instr.MachVInst,
  args : Array[@abi.VReg],
  results : Array[@abi.VReg],
  const_args : Map[Int, CallConstArg],
) -> Unit {
  if !ctx.abi_settings().enable_pinned_reg {
    abort("unpinned VMContext ABI not implemented yet")
  }
  let call_conv = ctx.call_conv_layout()
  // vmctx is pinned by the embedding ABI role supplied to lowering.
  let vmctx_preg : @abi.PReg = @lower.context_preg(ctx)

  // Classify user arguments by type
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for arg in args {
    match arg.class {
      Int => int_args.push((arg, Int))
      Float32 => float_args.push((arg, Float32))
      Float64 => float_args.push((arg, Float64))
      Vector => float_args.push((arg, Vector)) // SIMD uses Vn registers
    }
  }

  // Materialize constant overflow args before storing to stack.
  let max_int_reg_args = call_conv.user_arg_gprs.length()
  let max_float_reg_args = call_conv.arg_fprs.length()
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
  emit_wasm_overflow_arg_stores(ctx, block, int_args, float_args) |> ignore

  // vmctx constrained to the ISA's vmctx-arg register.
  call_inst.add_use_fixed(Physical(vmctx_preg), call_conv.context_arg)

  // Register int args (ISA-specific).
  let user_arg_gprs = call_conv.user_arg_gprs
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    let preg = user_arg_gprs[i]
    if const_args.get(vreg.id) is Some(value) {
      emit_call_const(block, vreg, value)
    }
    call_inst.add_use_fixed(Virtual(vreg), preg)
  }

  // Register float args (ISA-specific; float/vector share the same bank).
  let arg_fprs = call_conv.arg_fprs
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, arg_class) = float_args[i]
    let preg = @abi.PReg::{ index: arg_fprs[i].index, class: arg_class }
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

  // Define results with fixed register constraints (ISA-specific).
  // Classify results by type and assign to return GPR/FPR lists.
  let ret_gprs = call_conv.ret_gprs
  let ret_fprs = call_conv.ret_fprs
  let mut int_result_idx = 0
  let mut float_result_idx = 0
  for result in results {
    match result.class {
      Int => {
        call_inst.add_def_fixed({ reg: Virtual(result) }, {
          index: ret_gprs[int_result_idx].index,
          class: Int,
        })
        int_result_idx += 1
      }
      Float32 | Float64 | Vector => {
        // Float/Vector results go to V0, V1, ...
        // Use actual class for proper move size (32/64/128 bits)
        call_inst.add_def_fixed({ reg: Virtual(result) }, {
          index: ret_fprs[float_result_idx].index,
          class: result.class,
        })
        float_result_idx += 1
      }
    }
  }

  // Add clobbers for all caller-saved registers
  @lower.add_call_clobbers(ctx, call_inst)
  block.add_inst(call_inst)
  @lower.invalidate_context_pointer_cache(ctx)
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
  ctx : @lower.LoweringContext,
  block : @block.MachVBlock,
  func_ptr : @abi.VReg,
  args : Array[@abi.VReg],
  results : Array[@abi.VReg],
  const_args : Map[Int, CallConstArg],
) -> Unit {
  let num_args = args.length()
  let num_results = results.length()
  let call_inst = @instr.MachVInst::new(
    CallPtr(num_args, num_results, Internal),
  )
  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr), {
    index: @lower.scratch2_index(ctx),
    class: Int,
  })
  lower_wasm_call_common(ctx, block, call_inst, args, results, const_args)
}

///|
/// Lower a direct Wasm function call.
fn lower_wasm_call_direct(
  ctx : @lower.LoweringContext,
  block : @block.MachVBlock,
  func_idx : Int,
  args : Array[@abi.VReg],
  results : Array[@abi.VReg],
  const_args : Map[Int, CallConstArg],
) -> Unit {
  let num_args = args.length()
  let num_results = results.length()
  let call_inst = @instr.MachVInst::new(
    CallDirect(wasm_func_symbol(func_idx), num_args, num_results, Internal),
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
pub fn lower_return_call(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  func_idx : Int,
) -> Unit {
  // Load function address (patched at JIT module load time)
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_inst = @instr.MachVInst::new(
    LoadCodeAddr(wasm_func_symbol(func_idx)),
  )
  load_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_inst)

  // Get pinned vmctx.
  let vmctx_preg : @abi.PReg = @lower.context_preg(ctx)

  // Classify user arguments by type
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for operand in inst.operands {
    let vreg = ctx.get_vreg_for_use(operand, block)
    match vreg.class {
      Int => int_args.push((vreg, Int))
      Float32 => float_args.push((vreg, Float32))
      Float64 => float_args.push((vreg, Float64))
      Vector => float_args.push((vreg, Vector)) // SIMD uses Vn registers
    }
  }

  // Calculate overflow args count (user args, not including vmctx)
  let stack_arg_bytes = emit_wasm_overflow_arg_stores(
    ctx, block, int_args, float_args,
  )
  let call_conv = ctx.call_conv_layout()

  // Create ReturnCallIndirect instruction with fixed register constraints
  // Encode tail-call stack-bytes in opcode metadata.
  let call_inst = @instr.MachVInst::new(ReturnCallIndirect(stack_arg_bytes, 0))

  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr_vreg), {
    index: @lower.scratch2_index(ctx),
    class: Int,
  })

  // vmctx constrained to the ISA's vmctx-arg register.
  call_inst.add_use_fixed(Physical(vmctx_preg), call_conv.context_arg)

  // Register int args (ISA-specific).
  let user_arg_gprs = call_conv.user_arg_gprs
  let max_int_reg_args = user_arg_gprs.length()
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    call_inst.add_use_fixed(Virtual(vreg), {
      index: user_arg_gprs[i].index,
      class: Int,
    })
  }

  // Register float args (ISA-specific).
  let arg_fprs = call_conv.arg_fprs
  let max_float_reg_args = arg_fprs.length()
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, class) = float_args[i]
    call_inst.add_use_fixed(Virtual(vreg), { index: arg_fprs[i].index, class })
  }

  // No result defs for tail call (doesn't return to this function)
  // Add clobbers for caller-saved registers
  @lower.add_call_clobbers(ctx, call_inst)
  block.add_inst(call_inst)
}

///|
/// Lower return_call_indirect (indirect tail call)
/// Note: parameters handled in lowering via StoreToStack and add_use_fixed
pub fn lower_return_call_indirect(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  type_idx : Int,
  table_idx : Int,
  options : WasmLoweringOptions,
) -> Unit {
  // Get element index and load function pointer (similar to lower_call_indirect)
  guard inst.operands.length() > 0 else { return }
  let elem_idx_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Load table pointer
  let table_ptr_vreg : @abi.VReg = if table_idx == 0 {
    load_context_slot_pointer_from_pinned_context(
      ctx,
      block,
      options.context_slots.table0_base,
    )
  } else {
    let indirect_tables_vreg = ctx.machv_function().new_vreg(Int)
    let load_array_inst = @instr.MachVInst::new(
      Load(I64, context_slot_offset(ctx, options.context_slots.table_directory)),
    )
    load_array_inst.add_def({ reg: Virtual(indirect_tables_vreg) })
    load_array_inst.add_use(
      Physical({ index: @lower.context_index(ctx), class: Int }),
    )
    block.add_inst(load_array_inst)
    let table_offset = table_idx * options.context_slots.pointer_stride
    let ptr_vreg = ctx.machv_function().new_vreg(Int)
    let load_table_inst = @instr.MachVInst::new(Load(I64, table_offset))
    load_table_inst.add_def({ reg: Virtual(ptr_vreg) })
    load_table_inst.add_use(Virtual(indirect_tables_vreg))
    block.add_inst(load_table_inst)
    ptr_vreg
  }

  // Calculate address = table_ptr + (zext(elem_idx) << 4) (entry size = 16B).
  // Match Cranelift-style folded add+shift shape.
  let addr_vreg = ctx.machv_function().new_vreg(Int)
  let add_inst = @instr.MachVInst::new(AddExtend(Uxtw, 4))
  add_inst.add_def({ reg: Virtual(addr_vreg) })
  add_inst.add_use(Virtual(table_ptr_vreg))
  add_inst.add_use(Virtual(elem_idx_vreg))
  block.add_inst(add_inst)
  // Load raw function pointer
  let raw_func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_func_inst = @instr.MachVInst::new(Load(I64, 0))
  load_func_inst.add_def({ reg: Virtual(raw_func_ptr_vreg) })
  load_func_inst.add_use(Virtual(addr_vreg))
  block.add_inst(load_func_inst)

  // Clear FUNCREF_TAG (bit 61) from function pointer.
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let and_inst = @instr.MachVInst::new(AndImm(0xDFFFFFFFFFFFFFFFL, true))
  and_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  and_inst.add_use(Virtual(raw_func_ptr_vreg))
  block.add_inst(and_inst)

  let actual_type_vreg = ctx.machv_function().new_vreg(Int)
  let load_type_inst = @instr.MachVInst::new(Load(I32, 8))
  load_type_inst.add_def({ reg: Virtual(actual_type_vreg) })
  load_type_inst.add_use(Virtual(addr_vreg))
  block.add_inst(load_type_inst)

  // Type check (fast path); align with Cranelift behavior:
  // use exact check when subtype checks are unnecessary.
  let expected_type_idx = options.canonicalize_indirect_type_idx(type_idx)
  if options.use_subtype_indirect_check {
    let type_check = @instr.MachVInst::new(
      CallExternalIfI32NeImm(expected_type_idx, rt_gc_type_check_subtype(ctx)),
    )
    type_check.add_use(Virtual(actual_type_vreg))
    @lower.add_c_call_clobbers(ctx, type_check)
    block.add_inst(type_check)
  } else {
    emit_exact_indirect_type_check(
      ctx, block, actual_type_vreg, expected_type_idx,
    )
  }

  // Get pinned vmctx.
  let vmctx_preg : @abi.PReg = @lower.context_preg(ctx)

  // Classify user arguments (skip first operand which is elem_idx)
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for i in 1..<inst.operands.length() {
    let vreg = ctx.get_vreg_for_use(inst.operands[i], block)
    match vreg.class {
      Int => int_args.push((vreg, Int))
      Float32 => float_args.push((vreg, Float32))
      Float64 => float_args.push((vreg, Float64))
      Vector => float_args.push((vreg, Vector)) // SIMD uses Vn registers
    }
  }
  let stack_arg_bytes = emit_wasm_overflow_arg_stores(
    ctx, block, int_args, float_args,
  )
  let call_conv = ctx.call_conv_layout()

  // Create ReturnCallIndirect with fixed constraints
  // Encode tail-call stack-bytes in opcode metadata.
  let call_inst = @instr.MachVInst::new(ReturnCallIndirect(stack_arg_bytes, 0))

  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr_vreg), {
    index: @lower.scratch2_index(ctx),
    class: Int,
  })

  // vmctx constrained to the ISA's vmctx-arg register.
  call_inst.add_use_fixed(Physical(vmctx_preg), call_conv.context_arg)

  // Register int args (ISA-specific).
  let user_arg_gprs = call_conv.user_arg_gprs
  let max_int_reg_args = user_arg_gprs.length()
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    call_inst.add_use_fixed(Virtual(vreg), {
      index: user_arg_gprs[i].index,
      class: Int,
    })
  }

  // Register float args (ISA-specific).
  let arg_fprs = call_conv.arg_fprs
  let max_float_reg_args = arg_fprs.length()
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, class) = float_args[i]
    call_inst.add_use_fixed(Virtual(vreg), { index: arg_fprs[i].index, class })
  }
  @lower.add_call_clobbers(ctx, call_inst)
  block.add_inst(call_inst)
}

///|
/// Lower return_call_ref (tail call through function reference)
/// The func_ref is a tagged pointer (func_ptr | FUNCREF_TAG where FUNCREF_TAG = 0x2000000000000000)
/// Note: parameters handled in lowering
pub fn lower_return_call_ref(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  _type_idx : Int,
) -> Unit {
  guard inst.operands.length() > 0 else { return }
  let func_ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Strip FUNCREF_TAG (0x2000000000000000) to get raw function pointer
  // func_ptr = func_ref & 0xDFFFFFFFFFFFFFFF (clear bit 61)
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let and_inst = @instr.MachVInst::new(AndImm(0xDFFFFFFFFFFFFFFFL, true))
  and_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  and_inst.add_use(Virtual(func_ref_vreg))
  block.add_inst(and_inst)

  // Get vmctx
  let vmctx_preg : @abi.PReg = @lower.context_preg(ctx)

  // Classify user arguments (skip first operand which is func_ref)
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for i in 1..<inst.operands.length() {
    let vreg = ctx.get_vreg_for_use(inst.operands[i], block)
    match vreg.class {
      Int => int_args.push((vreg, Int))
      Float32 => float_args.push((vreg, Float32))
      Float64 => float_args.push((vreg, Float64))
      Vector => float_args.push((vreg, Vector)) // SIMD uses Vn registers
    }
  }
  let stack_arg_bytes = emit_wasm_overflow_arg_stores(
    ctx, block, int_args, float_args,
  )
  let call_conv = ctx.call_conv_layout()

  // Create ReturnCallIndirect with fixed constraints
  // Encode tail-call stack-bytes in opcode metadata.
  let call_inst = @instr.MachVInst::new(ReturnCallIndirect(stack_arg_bytes, 0))

  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr_vreg), {
    index: @lower.scratch2_index(ctx),
    class: Int,
  })

  // vmctx constrained to the ISA's vmctx-arg register.
  call_inst.add_use_fixed(Physical(vmctx_preg), call_conv.context_arg)

  // Register int args (ISA-specific).
  let user_arg_gprs = call_conv.user_arg_gprs
  let max_int_reg_args = user_arg_gprs.length()
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    call_inst.add_use_fixed(Virtual(vreg), {
      index: user_arg_gprs[i].index,
      class: Int,
    })
  }

  // Register float args (ISA-specific).
  let arg_fprs = call_conv.arg_fprs
  let max_float_reg_args = arg_fprs.length()
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, class) = float_args[i]
    call_inst.add_use_fixed(Virtual(vreg), { index: arg_fprs[i].index, class })
  }
  @lower.add_call_clobbers(ctx, call_inst)
  block.add_inst(call_inst)
}

///|
/// Lower an indirect function call (call_indirect)
/// The callee is already on the stack as a function table index
pub fn lower_call_indirect(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  expected_type_idx : Int,
  table_idx : Int,
  options : WasmLoweringOptions,
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
    // Fast path for table 0: load table0_base from the Wasm context on-demand.
    load_context_slot_pointer_from_pinned_context(
      ctx,
      block,
      options.context_slots.table0_base,
    )
  } else {
    // Slow path: load indirect_tables[table_idx] from context
    // 1. Load indirect_tables array pointer from the runtime context.
    let indirect_tables_vreg = ctx.machv_function().new_vreg(Int)
    let load_array_inst = @instr.MachVInst::new(
      Load(I64, context_slot_offset(ctx, options.context_slots.table_directory)),
    )
    load_array_inst.add_def({ reg: Virtual(indirect_tables_vreg) })
    load_array_inst.add_use(
      Physical({ index: @lower.context_index(ctx), class: Int }),
    )
    block.add_inst(load_array_inst)
    // 2. Calculate offset = table_idx * pointer size
    let table_offset = table_idx * options.context_slots.pointer_stride
    // 3. Load table pointer: [indirect_tables + offset]
    let ptr_vreg = ctx.machv_function().new_vreg(Int)
    let load_table_inst = @instr.MachVInst::new(Load(I64, table_offset))
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
  let result_vregs = @lower.collect_call_result_vregs(ctx, inst)

  // Create temporaries for call_indirect entry loads.
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let actual_type_vreg = ctx.machv_function().new_vreg(Int)

  // Step 1: Calculate address = table_ptr + (zext(elem_idx) << 4)
  // (entry size is 16 bytes).
  let addr_vreg = ctx.machv_function().new_vreg(Int)
  let add_inst = @instr.MachVInst::new(AddExtend(Uxtw, 4))
  add_inst.add_def({ reg: Virtual(addr_vreg) })
  add_inst.add_use(Virtual(table_ptr_vreg))
  add_inst.add_use(Virtual(elem_idx_vreg))
  block.add_inst(add_inst)

  // Step 2: Load function pointer from address (offset 0)
  let raw_func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_func_inst = @instr.MachVInst::new(Load(I64, 0))
  load_func_inst.add_def({ reg: Virtual(raw_func_ptr_vreg) })
  load_func_inst.add_use(Virtual(addr_vreg))
  block.add_inst(load_func_inst)

  // Step 2.5: Clear FUNCREF_TAG (bit 61) from function pointer.
  let and_inst = @instr.MachVInst::new(AndImm(0xDFFFFFFFFFFFFFFFL, true))
  and_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  and_inst.add_use(Virtual(raw_func_ptr_vreg))
  block.add_inst(and_inst)

  // Step 3: Load actual type index from address + 8
  let load_type_inst = @instr.MachVInst::new(Load(I32, 8))
  load_type_inst.add_def({ reg: Virtual(actual_type_vreg) })
  load_type_inst.add_use(Virtual(addr_vreg))
  block.add_inst(load_type_inst)

  // Step 5: Type check (fast path).
  //
  // Exact-match is by far the common case for call_indirect; avoid an
  // unconditional C call. On mismatch, fall back to the existing runtime helper
  // that implements full GC subtyping and traps on failure.
  let expected_canonical_type_idx = options.canonicalize_indirect_type_idx(
    expected_type_idx,
  )
  if options.use_subtype_indirect_check {
    let type_check = @instr.MachVInst::new(
      CallExternalIfI32NeImm(
        expected_canonical_type_idx,
        rt_gc_type_check_subtype(ctx),
      ),
    )
    type_check.add_use(Virtual(actual_type_vreg))
    @lower.add_c_call_clobbers(ctx, type_check)
    block.add_inst(type_check)
  } else {
    emit_exact_indirect_type_check(
      ctx, block, actual_type_vreg, expected_canonical_type_idx,
    )
  }

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
pub fn lower_call_ref(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
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
  let result_vregs = @lower.collect_call_result_vregs(ctx, inst)

  // Step 1: Strip FUNCREF_TAG (0x2000000000000000) to get raw function pointer
  // func_ptr = func_ref & 0xDFFFFFFFFFFFFFFF (clear bit 61)
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let and_inst = @instr.MachVInst::new(AndImm(0xDFFFFFFFFFFFFFFFL, true))
  and_inst.add_def({ reg: Virtual(func_ptr_vreg) })
  and_inst.add_use(Virtual(func_ref_vreg))
  block.add_inst(and_inst)

  // Step 2: Use Standard call lowering
  lower_wasm_call(
    ctx, block, func_ptr_vreg, arg_vregs, result_vregs, const_args,
  )
}

///|
/// Add clobber definitions for all caller-saved registers to a call instruction.
fn try_collect_call_arg_const(
  ctx : @lower.LoweringContext,
  value : @milkir.Value,
) -> CallConstArg? {
  if ctx.use_count(value.id) != 1 {
    return None
  }
  if @lower.find_defining_inst(ctx, value) is Some(inst) {
    match inst.opcode {
      Iconst(v) => Some(Int(v))
      Fconst(v) =>
        match value.ty {
          F32 => Some(F32(v.reinterpret_as_int64().to_int()))
          F64 => Some(F64(v.reinterpret_as_int64()))
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
  ctx : @lower.LoweringContext,
  operands : Array[@milkir.Value],
  block : @block.MachVBlock,
  start_idx : Int,
) -> (Array[@abi.VReg], Map[Int, CallConstArg]) {
  let arg_vregs : Array[@abi.VReg] = []
  let const_args : Map[Int, CallConstArg] = {}
  for i in start_idx..<operands.length() {
    let operand = operands[i]
    if try_collect_call_arg_const(ctx, operand) is Some(value) {
      let class = @lower.ir_type_to_reg_class(operand.ty)
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
/// Lower a direct function call
/// Cranelift-aligned strategy: use direct call fixups (`CallDirect`) for both
/// defined and imported functions. Imported targets are resolved from
/// `vmctx->func_table` when call fixups are applied at module load time.
pub fn lower_call(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  func_idx : Int,
) -> Unit {
  // Collect argument vregs, rematerializing single-use constants only for
  // direct calls. Indirect calls (imports or default path) keep original vregs.
  let use_const_args = ctx.num_imports() >= 0 && func_idx >= ctx.num_imports()
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
  let result_vregs = @lower.collect_call_result_vregs(ctx, inst)
  lower_wasm_call_direct(
    ctx, block, func_idx, arg_vregs, result_vregs, const_args,
  )
}
