///|
fn emit_load_vmctx_for_gc(
  ctx : @lower.LoweringContext,
  block : @block.Block,
) -> @abi.VReg {
  let vmctx_vreg = ctx.machv_function().new_vreg(Int)
  let vmctx_mov = @instr.Inst(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @lower.context_index(ctx), class: Int }))
  block.add_inst(vmctx_mov)
  vmctx_vreg
}

///|
fn emit_load_stack_args_base(
  ctx : @lower.LoweringContext,
  block : @block.Block,
) -> @abi.VReg {
  let sp_vreg = ctx.machv_function().new_vreg(Int)
  let load_sp = @instr.Inst(LoadSP)
  load_sp.add_def({ reg: Virtual(sp_vreg) })
  block.add_inst(load_sp)
  sp_vreg
}

///|
fn emit_load_safepoint_id(
  ctx : @lower.LoweringContext,
  block : @block.Block,
  root_count : Int,
) -> @abi.VReg {
  let safepoint_vreg = ctx.machv_function().new_vreg(Int)
  let load_safepoint = @instr.Inst(LoadSafepointId(root_count))
  load_safepoint.add_def({ reg: Virtual(safepoint_vreg) })
  block.add_inst(load_safepoint)
  safepoint_vreg
}

///|
fn emit_gc_struct_slow_alloc(
  ctx : @lower.LoweringContext,
  block : @block.Block,
  dst : @abi.VReg,
  type_idx : Int,
  num_fields : Int,
) -> Unit {
  let vmctx_vreg = emit_load_vmctx_for_gc(ctx, block)
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let fields_ptr_vreg = emit_load_stack_args_base(ctx, block)
  let num_fields_vreg = @lower.materialize_imm(
    ctx,
    block,
    num_fields.to_int64(),
  )
  let safepoint_vreg = emit_load_safepoint_id(ctx, block, num_fields)
  @lower.lower_c_libcall_direct(
    ctx,
    block,
    rt_gc_alloc_struct_slow(ctx),
    [
      vmctx_vreg, type_idx_vreg, fields_ptr_vreg, num_fields_vreg, safepoint_vreg,
    ],
    Some(dst),
  )
}

///|
fn emit_gc_array_slow_alloc(
  ctx : @lower.LoweringContext,
  block : @block.Block,
  dst : @abi.VReg,
  type_idx : Int,
  len_vreg : @abi.VReg,
  init_vreg : @abi.VReg,
) -> Unit {
  let vmctx_vreg = emit_load_vmctx_for_gc(ctx, block)
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let safepoint_vreg = emit_load_safepoint_id(ctx, block, 1)
  @lower.lower_c_libcall_direct(
    ctx,
    block,
    rt_gc_alloc_array_slow(ctx),
    [vmctx_vreg, type_idx_vreg, len_vreg, init_vreg, safepoint_vreg],
    Some(dst),
  )
}

///|
fn align_up(value : Int, align : Int) -> Int {
  (value + align - 1) / align * align
}

///|
fn gc_header_low(kind : Int, type_idx : Int, total_size : Int) -> Int64 {
  kind.to_int64() |
  ((type_idx & 0xFFFF).to_int64() << 16) |
  (total_size.to_int64() << 32)
}

///|
fn emit_load_context_slot(
  ctx : @lower.LoweringContext,
  block : @block.Block,
  offset : Int,
) -> @abi.VReg {
  let dst = ctx.new_vreg(Int)
  let inst = @instr.Inst(LoadPtr(I64, offset))
  inst.add_def({ reg: Virtual(dst) })
  inst.add_use(Physical(@lower.context_preg(ctx)))
  block.add_inst(inst)
  dst
}

///|
fn emit_store_context_slot(
  ctx : @lower.LoweringContext,
  block : @block.Block,
  offset : Int,
  value : @abi.VReg,
) -> Unit {
  let inst = @instr.Inst(StorePtr(I64, offset))
  inst.add_use(Physical(@lower.context_preg(ctx)))
  inst.add_use(Virtual(value))
  block.add_inst(inst)
}

///|
fn emit_load_ptr_i64(
  ctx : @lower.LoweringContext,
  block : @block.Block,
  base : @abi.VReg,
  offset : Int,
) -> @abi.VReg {
  let dst = ctx.new_vreg(Int)
  let inst = @instr.Inst(LoadPtr(I64, offset))
  inst.add_def({ reg: Virtual(dst) })
  inst.add_use(Virtual(base))
  block.add_inst(inst)
  dst
}

///|
fn emit_store_ptr_i64(
  block : @block.Block,
  base : @abi.VReg,
  offset : Int,
  value : @abi.VReg,
) -> Unit {
  let inst = @instr.Inst(StorePtr(I64, offset))
  inst.add_use(Virtual(base))
  inst.add_use(Virtual(value))
  block.add_inst(inst)
}

///|
fn emit_add_const_i64(
  ctx : @lower.LoweringContext,
  block : @block.Block,
  lhs : @abi.VReg,
  imm : Int,
) -> @abi.VReg {
  let rhs = @lower.materialize_imm(ctx, block, imm.to_int64())
  let dst = ctx.new_vreg(Int)
  let inst = @instr.Inst(Add(true))
  inst.add_def({ reg: Virtual(dst) })
  inst.add_use(Virtual(lhs))
  inst.add_use(Virtual(rhs))
  block.add_inst(inst)
  dst
}

///|
fn emit_jump_result(
  block : @block.Block,
  done : @block.Block,
  value : @abi.VReg,
) -> Unit {
  block.set_terminator(Jump(done.id, [Virtual(value)]))
}

///|
fn emit_gc_inline_alloc_from_stack(
  ctx : @lower.LoweringContext,
  block : @block.Block,
  dst : @abi.VReg,
  type_idx : Int,
  item_count : Int,
  kind : Int,
  payload_offset : Int,
  register_symbol : @instr.ExternalName,
  slow_symbol : @instr.ExternalName,
) -> @block.Block {
  let gc_header_size = 16
  let gc_align = 16
  let total_size = align_up(payload_offset + item_count * 8, gc_align)
  let header = gc_header_low(kind, type_idx, total_size)
  let layout = ctx.embedding_context_layout()
  let fast_block = ctx.machv_function().new_block()
  let slow_block = ctx.machv_function().new_block()
  let done_block = ctx.machv_function().new_block()
  done_block.params.push(dst)

  let obj = emit_load_context_slot(
    ctx,
    block,
    layout.require_allocation_cursor_offset(),
  )
  let end = emit_add_const_i64(ctx, block, obj, total_size)
  let limit = emit_load_context_slot(
    ctx,
    block,
    layout.require_allocation_limit_offset(),
  )
  block.set_terminator(
    BranchCmp(
      Virtual(end),
      Virtual(limit),
      Hi,
      true,
      slow_block.id,
      fast_block.id,
    ),
  )

  let header_vreg = @lower.materialize_imm(ctx, fast_block, header)
  emit_store_ptr_i64(fast_block, obj, 0, header_vreg)
  if kind == 1 {
    let count_vreg = @lower.materialize_imm(
      ctx,
      fast_block,
      item_count.to_int64(),
    )
    emit_store_ptr_i64(fast_block, obj, 8, count_vreg)
  } else {
    let zero_vreg = @lower.materialize_imm(ctx, fast_block, 0L)
    emit_store_ptr_i64(fast_block, obj, 8, zero_vreg)
    let len_vreg = @lower.materialize_imm(
      ctx,
      fast_block,
      item_count.to_int64(),
    )
    emit_store_ptr_i64(fast_block, obj, gc_header_size, len_vreg)
  }
  let stack_base = emit_load_stack_args_base(ctx, fast_block)
  for i in 0..<item_count {
    let value = emit_load_ptr_i64(ctx, fast_block, stack_base, i * 8)
    emit_store_ptr_i64(fast_block, obj, payload_offset + i * 8, value)
  }
  emit_store_context_slot(
    ctx,
    fast_block,
    layout.require_allocation_cursor_offset(),
    end,
  )
  let vmctx_fast = emit_load_vmctx_for_gc(ctx, fast_block)
  let total_size_vreg = @lower.materialize_imm(
    ctx,
    fast_block,
    total_size.to_int64(),
  )
  let fast_result = ctx.new_vreg(Int)
  @lower.lower_c_libcall_direct(
    ctx,
    fast_block,
    register_symbol,
    [vmctx_fast, obj, total_size_vreg],
    Some(fast_result),
  )
  emit_jump_result(fast_block, done_block, fast_result)

  let vmctx_slow = emit_load_vmctx_for_gc(ctx, slow_block)
  let type_idx_vreg = @lower.materialize_imm(
    ctx,
    slow_block,
    type_idx.to_int64(),
  )
  let fields_ptr_vreg = emit_load_stack_args_base(ctx, slow_block)
  let count_vreg = @lower.materialize_imm(
    ctx,
    slow_block,
    item_count.to_int64(),
  )
  let safepoint_vreg = emit_load_safepoint_id(ctx, slow_block, item_count)
  let slow_result = ctx.new_vreg(Int)
  @lower.lower_c_libcall_direct(
    ctx,
    slow_block,
    slow_symbol,
    [vmctx_slow, type_idx_vreg, fields_ptr_vreg, count_vreg, safepoint_vreg],
    Some(slow_result),
  )
  emit_jump_result(slow_block, done_block, slow_result)
  done_block
}

///|
/// Lower i31.new: Convert i32 to i31ref
/// Encoding: (value << 1) | 1 (positive odd for i31)
pub fn lower_i31_new(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)

  // Step 1: Zero-extend i32 to i64
  let ext_vreg = ctx.machv_function().new_vreg(Int)
  let extend_inst = @instr.Inst(Extend(Unsigned32To64))
  extend_inst.add_def({ reg: Virtual(ext_vreg) })
  extend_inst.add_use(Virtual(src))
  block.add_inst(extend_inst)

  // Step 2: Shift left by immediate 1
  let shifted_vreg = ctx.machv_function().new_vreg(Int)
  let shift_inst = @instr.Inst(ShlImm(1, true))
  shift_inst.add_def({ reg: Virtual(shifted_vreg) })
  shift_inst.add_use(Virtual(ext_vreg))
  block.add_inst(shift_inst)

  // Step 3: OR with immediate 1 to set low bit
  let or_inst = @instr.Inst(OrImm(1L, true))
  or_inst.add_def({ reg: Virtual(dst) })
  or_inst.add_use(Virtual(shifted_vreg))
  block.add_inst(or_inst)
}

///|
/// Lower i31.get_s: Sign-extend 31 bits to i32
/// Encoding is (value << 1) | 1, so:
/// 1. Check for null (0) and trap
/// 2. Shift right by 1 to decode (removes the tag bit)
/// 3. Sign-extend from 31 bits
pub fn lower_i31_get_s(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)

  // Step 0: Null check - trap if i31 ref is null (0)
  let trap_inst = @instr.Inst(TrapIfZero(true, 2))
  trap_inst.add_use(Virtual(src))
  block.add_inst(trap_inst)

  // Step 1: Shift right by immediate 1 to decode the i31 value (64-bit)
  let decoded = ctx.new_vreg(Int)
  let lsr_inst = @instr.Inst(LShrImm(1, true))
  lsr_inst.add_def({ reg: Virtual(decoded) })
  lsr_inst.add_use(Virtual(src))
  block.add_inst(lsr_inst)

  // Step 2: Truncate to 32 bits
  let tmp = ctx.new_vreg(Int)
  let trunc_inst = @instr.Inst(Truncate)
  trunc_inst.add_def({ reg: Virtual(tmp) })
  trunc_inst.add_use(Virtual(decoded))
  block.add_inst(trunc_inst)

  // Step 3: Sign-extend from 31 bits by shifting left then arithmetic right
  let tmp2 = ctx.new_vreg(Int)
  let shl_inst = @instr.Inst(ShlImm(1, false))
  shl_inst.add_def({ reg: Virtual(tmp2) })
  shl_inst.add_use(Virtual(tmp))
  block.add_inst(shl_inst)
  let asr_inst = @instr.Inst(AShrImm(1, false))
  asr_inst.add_def({ reg: Virtual(dst) })
  asr_inst.add_use(Virtual(tmp2))
  block.add_inst(asr_inst)
}

///|
/// Lower i31.get_u: Zero-extend 31 bits
/// Encoding is (value << 1) | 1, so:
/// 1. Check for null (0) and trap
/// 2. Shift right by 1 to decode (removes the tag bit)
/// 3. Mask with 0x7FFFFFFF for 31 bits
pub fn lower_i31_get_u(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)

  // Step 0: Null check - trap if i31 ref is null (0)
  let trap_inst = @instr.Inst(TrapIfZero(true, 2))
  trap_inst.add_use(Virtual(src))
  block.add_inst(trap_inst)

  // Step 1: Shift right by immediate 1 to decode the i31 value (64-bit)
  let decoded = ctx.new_vreg(Int)
  let lsr_inst = @instr.Inst(LShrImm(1, true))
  lsr_inst.add_def({ reg: Virtual(decoded) })
  lsr_inst.add_use(Virtual(src))
  block.add_inst(lsr_inst)

  // Step 2: Truncate to 32 bits
  let tmp = ctx.new_vreg(Int)
  let trunc_inst = @instr.Inst(Truncate)
  trunc_inst.add_def({ reg: Virtual(tmp) })
  trunc_inst.add_use(Virtual(decoded))
  block.add_inst(trunc_inst)

  // Step 3: Mask with 0x7FFFFFFF for 31 bits (already decoded, just ensure upper bit is clear)
  let mask = ctx.new_vreg(Int)
  let load_mask = @instr.Inst(LoadConst(0x7FFFFFFFL))
  load_mask.add_def({ reg: Virtual(mask) })
  block.add_inst(load_mask)
  let and_inst = @instr.Inst(And(false))
  and_inst.add_def({ reg: Virtual(dst) })
  and_inst.add_use(Virtual(tmp))
  and_inst.add_use(Virtual(mask))
  block.add_inst(and_inst)
}

///|
/// Lower GC type conversions (any.convert_extern, extern.convert_any)
/// These are no-ops in the JIT - just pass the reference through
pub fn lower_gc_convert(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  // Just move the value - the representation is the same
  let machv_inst = @instr.Inst(Move)
  machv_inst.add_def({ reg: Virtual(dst) })
  machv_inst.add_use(Virtual(src))
  block.add_inst(machv_inst)
}

///|
/// Lower ref.test: Test if reference matches type
/// Uses runtime libcall: gc_ref_test_impl(ref, type_idx, nullable) -> 0 or 1
pub fn lower_ref_test(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  nullable : Bool,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Materialize immediate arguments
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let nullable_vreg = @lower.materialize_imm(
    ctx,
    block,
    if nullable {
      1L
    } else {
      0L
    },
  )
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_ref_test(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_ref_test_impl(ref, type_idx, nullable) -> result
  @lower.lower_c_libcall(
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
pub fn lower_ref_cast(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  nullable : Bool,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Materialize immediate arguments
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let nullable_vreg = @lower.materialize_imm(
    ctx,
    block,
    if nullable {
      1L
    } else {
      0L
    },
  )
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_ref_cast(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_ref_cast_impl(ref, type_idx, nullable) -> result
  @lower.lower_c_libcall(
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
pub fn lower_ref_eq(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let ref1_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let ref2_vreg = ctx.get_vreg_for_use(inst.operands[1], block)

  // Compare two references as i64 values
  // Use Cmp(Eq, true) for 64-bit equality comparison
  let cmp_inst = @instr.Inst(Cmp(Eq, true))
  cmp_inst.add_def({ reg: Virtual(dst) })
  cmp_inst.add_use(Virtual(ref1_vreg))
  cmp_inst.add_use(Virtual(ref2_vreg))
  block.add_inst(cmp_inst)
}

///|
/// Lower struct.new: Allocate struct with field values
/// Uses runtime libcall:
///   gc_alloc_struct_slow(vmctx, type_idx, fields_ptr, num_fields, safepoint_id) -> struct_ref
pub fn lower_struct_new(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
) -> @block.Block {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let num_fields = inst.operands.length()

  // Fast path: inline bump allocation with slow-path fallback.
  // Keep `struct.new_default` as pure slow path (num_fields == 0).
  // Keep a conservative field-count cap for inline lowering.
  if num_fields > 0 && num_fields <= 4092 {
    // Use outgoing args area as temporary field buffer.
    let stack_space = (num_fields * 8 + 15) / 16 * 16
    ctx.machv_function().update_max_outgoing_args_size(stack_space)
    for i in 0..<num_fields {
      let field_vreg = ctx.get_vreg_for_use(inst.operands[i], block)
      let offset = i * 8
      let store = @instr.Inst(StoreToStack(offset))
      store.add_use(Virtual(field_vreg))
      block.add_inst(store)
    }
    return emit_gc_inline_alloc_from_stack(
      ctx,
      block,
      dst,
      type_idx,
      num_fields,
      1,
      16,
      rt_gc_register_struct_inline(ctx),
      rt_gc_alloc_struct_slow(ctx),
    )
  }

  // Fallback path: precise slow alloc call with safepoint metadata.
  if num_fields > 0 {
    let stack_space = (num_fields * 8 + 15) / 16 * 16
    ctx.machv_function().update_max_outgoing_args_size(stack_space)
    for i in 0..<num_fields {
      let field_vreg = ctx.get_vreg_for_use(inst.operands[i], block)
      let offset = i * 8
      let store = @instr.Inst(StoreToStack(offset))
      store.add_use(Virtual(field_vreg))
      block.add_inst(store)
    }
  }
  emit_gc_struct_slow_alloc(ctx, block, dst, type_idx, num_fields)
  block
}

///|
/// Lower struct.new_default: Allocate struct with default values
/// Uses runtime libcall:
///   gc_alloc_struct_slow(vmctx, type_idx, null, 0, safepoint_id) -> struct_ref
pub fn lower_struct_new_default(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)

  emit_gc_struct_slow_alloc(ctx, block, dst, type_idx, 0)
}

///|
/// Lower struct.get: Get struct field value
/// Uses runtime libcall: gc_struct_get_impl(ref, type_idx, field_idx) -> value
pub fn lower_struct_get(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  field_idx : Int,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Materialize immediate arguments
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let field_idx_vreg = @lower.materialize_imm(ctx, block, field_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_struct_get(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Check if result is a float type - C libcall returns int64, need bitcast
  let is_float = result.ty is (F32 | F64)
  if is_float {
    // For float results: call returns int64, then bitcast to float
    let int_result = ctx.machv_function().new_vreg(Int)
    @lower.lower_c_libcall(
      ctx,
      block,
      func_ptr_vreg,
      [ref_vreg, type_idx_vreg, field_idx_vreg],
      Some(int_result),
    )
    // Bitcast from int to float
    let bitcast = @instr.Inst(Bitcast)
    bitcast.add_def({ reg: Virtual(dst) })
    bitcast.add_use(Virtual(int_result))
    block.add_inst(bitcast)
  } else {
    // For integer results: call returns directly
    @lower.lower_c_libcall(
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
pub fn lower_struct_get_s(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  field_idx : Int,
  byte_width : Int,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Materialize immediate arguments
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let field_idx_vreg = @lower.materialize_imm(ctx, block, field_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_struct_get(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call and get raw value
  let raw_result = ctx.machv_function().new_vreg(Int)
  @lower.lower_c_libcall(
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
    let ext = @instr.Inst(Extend(Signed8To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else if byte_width == 2 {
    // SXTH: Sign extend halfword to 32-bit
    let ext = @instr.Inst(Extend(Signed16To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else {
    abort("validated struct_get_s has invalid packed byte width \{byte_width}")
  }
}

///|
/// Lower struct.get_u: Get struct field value with zero extension
/// Uses runtime libcall then zero extends based on byte_width
pub fn lower_struct_get_u(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  field_idx : Int,
  byte_width : Int,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Materialize immediate arguments
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let field_idx_vreg = @lower.materialize_imm(ctx, block, field_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_struct_get(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call and get raw value
  let raw_result = ctx.machv_function().new_vreg(Int)
  @lower.lower_c_libcall(
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
    let ext = @instr.Inst(Extend(Unsigned8To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else if byte_width == 2 {
    // UXTH: Zero extend halfword to 32-bit
    let ext = @instr.Inst(Extend(Unsigned16To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else {
    abort("validated struct_get_u has invalid packed byte width \{byte_width}")
  }
}

///|
/// Lower struct.set: Set struct field value
/// Uses runtime libcall: gc_struct_set_impl(ref, type_idx, field_idx, value)
pub fn lower_struct_set(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  field_idx : Int,
) -> Unit {
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let val_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  // Materialize immediate arguments
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let field_idx_vreg = @lower.materialize_imm(ctx, block, field_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_struct_set(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Check if value is a float type - C libcall expects int64, need bitcast
  let is_float = inst.operands[1].ty is (F32 | F64)
  let actual_val_vreg = if is_float {
    // For float values: bitcast to int before passing to C function
    let int_val = ctx.machv_function().new_vreg(Int)
    let bitcast = @instr.Inst(Bitcast)
    bitcast.add_def({ reg: Virtual(int_val) })
    bitcast.add_use(Virtual(val_vreg))
    block.add_inst(bitcast)
    int_val
  } else {
    val_vreg
  }
  // Call: gc_struct_set_impl(ref, type_idx, field_idx, value)
  @lower.lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, field_idx_vreg, actual_val_vreg],
    None,
  )
}

///|
/// Lower array.new: Allocate array with init value and length
/// Uses runtime libcall:
///   gc_alloc_array_slow(vmctx, type_idx, length, init_value, safepoint_id) -> array_ref
pub fn lower_array_new(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let init_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let len_vreg = ctx.get_vreg_for_use(inst.operands[1], block)

  // Check if init value is float - C libcall expects int64, need bitcast
  let is_float = inst.operands[0].ty is (F32 | F64)
  let actual_init_vreg = if is_float {
    let int_val = ctx.machv_function().new_vreg(Int)
    let bitcast = @instr.Inst(Bitcast)
    bitcast.add_def({ reg: Virtual(int_val) })
    bitcast.add_use(Virtual(init_vreg))
    block.add_inst(bitcast)
    int_val
  } else {
    init_vreg
  }
  emit_gc_array_slow_alloc(
    ctx, block, dst, type_idx, len_vreg, actual_init_vreg,
  )
}

///|
/// Lower array.new_default: Allocate array with default values
/// Uses runtime libcall:
///   gc_alloc_array_slow(vmctx, type_idx, length, init_value=0, safepoint_id) -> array_ref
pub fn lower_array_new_default(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let len_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Load default value (0) for the init value.
  let zero_vreg = @lower.materialize_imm(ctx, block, 0L)
  emit_gc_array_slow_alloc(ctx, block, dst, type_idx, len_vreg, zero_vreg)
}

///|
/// Lower array.new_fixed: Allocate fixed-size array with element values
/// Uses runtime libcalls: gc_alloc_array_slow and gc_array_set_impl
pub fn lower_array_new_fixed(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  len : Int,
) -> @block.Block {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)

  // Fast path: inline fixed-array allocation with slow-path fallback.
  // Keep a conservative element-count cap for inline lowering.
  if len > 0 && len <= 4092 {
    // Spill all element values to outgoing args area as contiguous int64_t[].
    let stack_space = (len * 8 + 15) / 16 * 16
    ctx.machv_function().update_max_outgoing_args_size(stack_space)
    let is_float = inst.operands[0].ty is (F32 | F64)
    for i in 0..<len {
      let elem_vreg = ctx.get_vreg_for_use(inst.operands[i], block)
      let actual_elem = if is_float {
        let int_val = ctx.machv_function().new_vreg(Int)
        let bitcast = @instr.Inst(Bitcast)
        bitcast.add_def({ reg: Virtual(int_val) })
        bitcast.add_use(Virtual(elem_vreg))
        block.add_inst(bitcast)
        int_val
      } else {
        elem_vreg
      }
      let store = @instr.Inst(StoreToStack(i * 8))
      store.add_use(Virtual(actual_elem))
      block.add_inst(store)
    }
    return emit_gc_inline_alloc_from_stack(
      ctx,
      block,
      dst,
      type_idx,
      len,
      2,
      24,
      rt_gc_register_array_inline(ctx),
      rt_gc_alloc_array_from_values_slow(ctx),
    )
  }

  // Fallback path: precise slow alloc call with safepoint metadata.
  let len_vreg = @lower.materialize_imm(ctx, block, len.to_int64())
  if len == 0 {
    let zero_vreg = @lower.materialize_imm(ctx, block, 0L)
    emit_gc_array_slow_alloc(ctx, block, dst, type_idx, zero_vreg, zero_vreg)
    return block
  }

  let is_float = inst.operands[0].ty is (F32 | F64)
  let first_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let actual_first = if is_float {
    let int_val = ctx.machv_function().new_vreg(Int)
    let bitcast = @instr.Inst(Bitcast)
    bitcast.add_def({ reg: Virtual(int_val) })
    bitcast.add_use(Virtual(first_vreg))
    block.add_inst(bitcast)
    int_val
  } else {
    first_vreg
  }
  emit_gc_array_slow_alloc(ctx, block, dst, type_idx, len_vreg, actual_first)
  if len > 1 {
    let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
    let array_set_fp = ctx.machv_function().new_vreg(Int)
    let load_set_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_set(ctx)))
    load_set_fp.add_def({ reg: Virtual(array_set_fp) })
    block.add_inst(load_set_fp)
    for i in 1..<len {
      let elem_vreg = ctx.get_vreg_for_use(inst.operands[i], block)
      let actual_elem = if is_float {
        let int_val = ctx.machv_function().new_vreg(Int)
        let bitcast = @instr.Inst(Bitcast)
        bitcast.add_def({ reg: Virtual(int_val) })
        bitcast.add_use(Virtual(elem_vreg))
        block.add_inst(bitcast)
        int_val
      } else {
        elem_vreg
      }
      let idx_vreg = @lower.materialize_imm(ctx, block, i.to_int64())
      @lower.lower_c_libcall(
        ctx,
        block,
        array_set_fp,
        [dst, type_idx_vreg, idx_vreg, actual_elem],
        None,
      )
    }
  }
  block
}

///|
/// Lower array.get: Get array element
/// Uses runtime libcall: gc_array_get_impl(ref, type_idx, idx) -> value
pub fn lower_array_get(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let idx_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  // Materialize type_idx
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_get(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Check if result is a float type - C libcall returns int64, need bitcast
  let is_float = result.ty is (F32 | F64)
  if is_float {
    // For float results: call returns int64, then bitcast to float
    let int_result = ctx.machv_function().new_vreg(Int)
    @lower.lower_c_libcall(
      ctx,
      block,
      func_ptr_vreg,
      [ref_vreg, type_idx_vreg, idx_vreg],
      Some(int_result),
    )
    // Bitcast from int to float
    let bitcast = @instr.Inst(Bitcast)
    bitcast.add_def({ reg: Virtual(dst) })
    bitcast.add_use(Virtual(int_result))
    block.add_inst(bitcast)
  } else {
    // For integer results: call returns directly
    @lower.lower_c_libcall(
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
pub fn lower_array_get_s(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  byte_width : Int,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let idx_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  // Materialize type_idx
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_get(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call and get raw value
  let raw_result = ctx.machv_function().new_vreg(Int)
  @lower.lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, idx_vreg],
    Some(raw_result),
  )
  // Sign extend based on byte_width
  if byte_width == 1 {
    let ext = @instr.Inst(Extend(Signed8To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else if byte_width == 2 {
    let ext = @instr.Inst(Extend(Signed16To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else {
    abort("validated array_get_s has invalid packed byte width \{byte_width}")
  }
}

///|
/// Lower array.get_u: Get array element with zero extension
/// Uses runtime libcall then zero extends based on byte_width
pub fn lower_array_get_u(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  byte_width : Int,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let idx_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  // Materialize type_idx
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_get(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call and get raw value
  let raw_result = ctx.machv_function().new_vreg(Int)
  @lower.lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [ref_vreg, type_idx_vreg, idx_vreg],
    Some(raw_result),
  )
  // Zero extend based on byte_width
  if byte_width == 1 {
    let ext = @instr.Inst(Extend(Unsigned8To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else if byte_width == 2 {
    let ext = @instr.Inst(Extend(Unsigned16To32))
    ext.add_def({ reg: Virtual(dst) })
    ext.add_use(Virtual(raw_result))
    block.add_inst(ext)
  } else {
    abort("validated array_get_u has invalid packed byte width \{byte_width}")
  }
}

///|
/// Lower array.set: Set array element
/// Uses runtime libcall: gc_array_set_impl(ref, type_idx, idx, value)
pub fn lower_array_set(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
) -> Unit {
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let idx_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  let val_vreg = ctx.get_vreg_for_use(inst.operands[2], block)
  // Materialize type_idx
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_set(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Check if value is a float type - C libcall expects int64, need bitcast
  let is_float = inst.operands[2].ty is (F32 | F64)
  let actual_val_vreg = if is_float {
    // For float values: bitcast to int before passing to C function
    let int_val = ctx.machv_function().new_vreg(Int)
    let bitcast = @instr.Inst(Bitcast)
    bitcast.add_def({ reg: Virtual(int_val) })
    bitcast.add_use(Virtual(val_vreg))
    block.add_inst(bitcast)
    int_val
  } else {
    val_vreg
  }
  // Call: gc_array_set_impl(ref, type_idx, idx, value)
  @lower.lower_c_libcall(
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
pub fn lower_array_len(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  let result = inst.first_result().unwrap()
  let dst = ctx.get_vreg(result)
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_len(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_array_len_impl(ref) -> result
  @lower.lower_c_libcall(ctx, block, func_ptr_vreg, [ref_vreg], Some(dst))
}

///|
/// Lower array.fill: Fill array elements with a value
/// Uses runtime libcall: gc_array_fill_impl(ref, offset, value, count)
pub fn lower_array_fill(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  _type_idx : Int,
) -> Unit {
  // Operands: ref, offset, value, count
  let ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let offset_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  let val_vreg = ctx.get_vreg_for_use(inst.operands[2], block)
  let count_vreg = ctx.get_vreg_for_use(inst.operands[3], block)
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_fill(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_array_fill_impl(ref, offset, value, count)
  @lower.lower_c_libcall(
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
pub fn lower_array_copy(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
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
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_copy(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Call: gc_array_copy_impl(dst_ref, dst_off, src_ref, src_off, count)
  @lower.lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [dst_ref_vreg, dst_off_vreg, src_ref_vreg, src_off_vreg, count_vreg],
    None,
  )
}

///|
/// Lower array.new_data instruction
/// Creates an array from a data segment
pub fn lower_array_new_data(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  data_idx : Int,
) -> Unit {
  // Operands: data_offset, length
  let data_off_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let length_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  let result_vreg = match inst.first_result() {
    Some(r) => ctx.get_vreg(r)
    None => ctx.machv_function().new_vreg(Int)
  }
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_new_data(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Get vmctx
  let vmctx_vreg = ctx.machv_function().new_vreg(Int)
  let vmctx_mov = @instr.Inst(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @lower.context_index(ctx), class: Int }))
  block.add_inst(vmctx_mov)
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let data_idx_vreg = @lower.materialize_imm(ctx, block, data_idx.to_int64())
  // Call: gc_array_new_data_impl(vmctx, type_idx, data_idx, data_off, length) -> arrayref
  @lower.lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, type_idx_vreg, data_idx_vreg, data_off_vreg, length_vreg],
    Some(result_vreg),
  )
}

///|
/// Lower array.new_elem instruction
/// Creates an array from an element segment
pub fn lower_array_new_elem(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  elem_idx : Int,
) -> Unit {
  // Operands: elem_offset, length
  let elem_off_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let length_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  let result_vreg = match inst.first_result() {
    Some(r) => ctx.get_vreg(r)
    None => ctx.machv_function().new_vreg(Int)
  }
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_new_elem(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Get vmctx
  let vmctx_vreg = ctx.machv_function().new_vreg(Int)
  let vmctx_mov = @instr.Inst(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @lower.context_index(ctx), class: Int }))
  block.add_inst(vmctx_mov)
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let elem_idx_vreg = @lower.materialize_imm(ctx, block, elem_idx.to_int64())
  // Call: gc_array_new_elem_impl(vmctx, type_idx, elem_idx, elem_off, length) -> arrayref
  @lower.lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, type_idx_vreg, elem_idx_vreg, elem_off_vreg, length_vreg],
    Some(result_vreg),
  )
}

///|
/// Lower array.init_data instruction
/// Initializes array elements from a data segment
pub fn lower_array_init_data(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  data_idx : Int,
) -> Unit {
  // Operands: arrayref, arr_offset, data_offset, length
  let array_ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let arr_off_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  let data_off_vreg = ctx.get_vreg_for_use(inst.operands[2], block)
  let length_vreg = ctx.get_vreg_for_use(inst.operands[3], block)
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_init_data(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Get vmctx
  let vmctx_vreg = ctx.machv_function().new_vreg(Int)
  let vmctx_mov = @instr.Inst(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @lower.context_index(ctx), class: Int }))
  block.add_inst(vmctx_mov)
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let data_idx_vreg = @lower.materialize_imm(ctx, block, data_idx.to_int64())
  // Call: gc_array_init_data_impl(vmctx, type_idx, data_idx, arrayref, arr_off, data_off, length)
  @lower.lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [
      vmctx_vreg, type_idx_vreg, data_idx_vreg, array_ref_vreg, arr_off_vreg, data_off_vreg,
      length_vreg,
    ],
    None,
  )
}

///|
/// Lower array.init_elem instruction
/// Initializes array elements from an element segment
pub fn lower_array_init_elem(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  type_idx : Int,
  elem_idx : Int,
) -> Unit {
  // Operands: arrayref, arr_offset, elem_offset, length
  let array_ref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
  let arr_off_vreg = ctx.get_vreg_for_use(inst.operands[1], block)
  let elem_off_vreg = ctx.get_vreg_for_use(inst.operands[2], block)
  let length_vreg = ctx.get_vreg_for_use(inst.operands[3], block)
  // Load function pointer
  let func_ptr_vreg = ctx.machv_function().new_vreg(Int)
  let load_fp = @instr.Inst(LoadExternalFuncAddr(rt_gc_array_init_elem(ctx)))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)
  // Get vmctx
  let vmctx_vreg = ctx.machv_function().new_vreg(Int)
  let vmctx_mov = @instr.Inst(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @lower.context_index(ctx), class: Int }))
  block.add_inst(vmctx_mov)
  let type_idx_vreg = @lower.materialize_imm(ctx, block, type_idx.to_int64())
  let elem_idx_vreg = @lower.materialize_imm(ctx, block, elem_idx.to_int64())
  // Call: gc_array_init_elem_impl(vmctx, type_idx, elem_idx, arrayref, arr_off, elem_off, length)
  @lower.lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [
      vmctx_vreg, type_idx_vreg, elem_idx_vreg, array_ref_vreg, arr_off_vreg, elem_off_vreg,
      length_vreg,
    ],
    None,
  )
}
