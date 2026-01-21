// Note: emit_bounds_check and emit_load_memory_base removed
// Memory bounds checking is now done at IR translation time via FuncEnvironment

///|
/// Emit instruction to load func_table from vmctx on-demand (Standard)
/// Returns a virtual register containing func_table pointer
/// This is called before function calls to get the function table base address
fn emit_load_func_table(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
) -> @abi.VReg {
  if ctx.func_table_cache.get(block.id) is Some(vreg) {
    return vreg
  }
  let func_table_vreg = ctx.vcode_func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(Load(I64, @abi.VMCTX_FUNC_TABLE_OFFSET))
  load_inst.add_def({ reg: Virtual(func_table_vreg) })
  load_inst.add_use(Physical({ index: @abi.REG_VMCTX, class: Int })) // X19 = vmctx
  block.add_inst(load_inst)
  ctx.func_table_cache.set(block.id, func_table_vreg)
  func_table_vreg
}

///|
/// Emit instruction to load table0_base from vmctx on-demand (Standard)
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
  guard inst.first_result() is Some(result) else { return }
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

// Note: lower_load, lower_store, lower_load_narrow, lower_store_narrow removed
// Memory bounds checking is now done at IR translation time via FuncEnvironment
// VCode lowering now uses LoadPtr/StorePtr/LoadPtrNarrow/StorePtrNarrow directly

///|
/// Lower LoadMemBase - load linear memory base pointer from VMContext.
/// memidx: memory index for multi-memory support
fn lower_load_mem_base(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  memidx : Int,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  if inst.operands.length() != 1 {
    return
  }
  let result_vreg = ctx.get_vreg(result)
  let load_inst = @instr.VCodeInst::new(LoadMemBase(memidx))
  load_inst.add_def({ reg: Virtual(result_vreg) })
  if ctx.abi_settings.enable_pinned_reg {
    load_inst.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  } else {
    let vmctx_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
    load_inst.add_use(Virtual(vmctx_vreg))
  }
  block.add_inst(load_inst)
}

///|
/// Lower memory.grow instruction
/// memory.grow takes a delta (number of pages to grow) and returns the previous size or -1
/// memidx: memory index for multi-memory support
fn lower_memory_grow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  memidx : Int,
  max_pages : Int?,
) -> Unit {
  // Get the delta operand
  let delta_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Get the result vreg
  guard inst.first_result() is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Check if result type is I64 (memory64)
  let is_memory64 = result.ty is @ir.Type::I64

  // Lower to a C call:
  //   wasmoon_jit_memory_grow(vmctx, memidx, delta, max_pages) -> i32
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(MemoryGrow))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let memidx_vreg = materialize_imm(ctx, block, memidx.to_int64())
  let max_pages_value = max_pages.unwrap_or(-1)
  let max_pages_vreg = materialize_imm(ctx, block, max_pages_value.to_int64())

  // For memory64, use a temporary vreg for the i32 result, then sign-extend to i64
  let call_result_vreg = if is_memory64 {
    ctx.vcode_func.new_vreg(Int)
  } else {
    result_vreg
  }
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, memidx_vreg, delta_vreg, max_pages_vreg],
    Some(call_result_vreg),
  )

  // For memory64, sign-extend the i32 result to i64
  // This handles -1 (failure) properly: 0xFFFFFFFF -> 0xFFFFFFFFFFFFFFFF
  if is_memory64 {
    let extend_inst = @instr.VCodeInst::new(Extend(Signed32To64))
    extend_inst.add_def({ reg: Virtual(result_vreg) })
    extend_inst.add_use(Virtual(call_result_vreg))
    block.add_inst(extend_inst)
  }
}

///|
/// Lower memory.size instruction
/// memory.size returns the current memory size in pages
/// memidx: memory index for multi-memory support
fn lower_memory_size(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  memidx : Int,
) -> Unit {
  // Get the result vreg
  guard inst.first_result() is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Check if result type is I64 (memory64)
  let is_memory64 = result.ty is @ir.Type::I64

  // Lower to a C call:
  //   wasmoon_jit_memory_size(vmctx, memidx) -> i32
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(MemorySize))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let memidx_vreg = materialize_imm(ctx, block, memidx.to_int64())

  // For memory64, use a temporary vreg for the i32 result, then zero-extend to i64
  // (memory.size is always non-negative, so zero-extend is fine)
  let call_result_vreg = if is_memory64 {
    ctx.vcode_func.new_vreg(Int)
  } else {
    result_vreg
  }
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, memidx_vreg],
    Some(call_result_vreg),
  )

  // For memory64, zero-extend the i32 result to i64
  if is_memory64 {
    let extend_inst = @instr.VCodeInst::new(Extend(Unsigned32To64))
    extend_inst.add_def({ reg: Virtual(result_vreg) })
    extend_inst.add_use(Virtual(call_result_vreg))
    block.add_inst(extend_inst)
  }
}

///|
/// Lower memory.fill instruction
/// memory.fill fills a memory region with a byte value
/// memidx: memory index for multi-memory support
fn lower_memory_fill(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  memidx : Int,
) -> Unit {
  // Get the operands: dst, val, size
  guard inst.operands.length() >= 3 else { return }
  let dst = ctx.get_vreg_for_use(inst.operands[0], block)
  let val = ctx.get_vreg_for_use(inst.operands[1], block)
  let size = ctx.get_vreg_for_use(inst.operands[2], block)

  // Lower to a C call:
  //   wasmoon_jit_memory_fill(vmctx, memidx, dst, val, size)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(MemoryFill))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let memidx_vreg = materialize_imm(ctx, block, memidx.to_int64())
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, memidx_vreg, dst, val, size],
    None,
  )
}

///|
/// Lower memory.copy instruction
/// memory.copy copies a memory region (handles overlapping regions correctly)
/// dst_memidx: destination memory index for multi-memory support
/// src_memidx: source memory index for multi-memory support
fn lower_memory_copy(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  dst_memidx : Int,
  src_memidx : Int,
) -> Unit {
  // Get the operands: dst, src, size
  guard inst.operands.length() >= 3 else { return }
  let dst = ctx.get_vreg_for_use(inst.operands[0], block)
  let src = ctx.get_vreg_for_use(inst.operands[1], block)
  let size = ctx.get_vreg_for_use(inst.operands[2], block)

  // Lower to a C call:
  //   wasmoon_jit_memory_copy(vmctx, dst_memidx, src_memidx, dst, src, size)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(MemoryCopy))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let dst_memidx_vreg = materialize_imm(ctx, block, dst_memidx.to_int64())
  let src_memidx_vreg = materialize_imm(ctx, block, src_memidx.to_int64())
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, dst_memidx_vreg, src_memidx_vreg, dst, src, size],
    None,
  )
}

///|
/// Lower memory.init instruction
/// memory.init copies data from a data segment to memory
/// memidx: memory index, data_idx: data segment index
fn lower_memory_init(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  memidx : Int,
  data_idx : Int,
) -> Unit {
  // Get the operands: dst, src, size
  guard inst.operands.length() >= 3 else { return }
  let dst = ctx.get_vreg_for_use(inst.operands[0], block)
  let src = ctx.get_vreg_for_use(inst.operands[1], block)
  let size = ctx.get_vreg_for_use(inst.operands[2], block)

  // Lower to a C call:
  //   wasmoon_jit_memory_init(vmctx, memidx, data_idx, dst, src, size)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(MemoryInit))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let memidx_vreg = materialize_imm(ctx, block, memidx.to_int64())
  let data_idx_vreg = materialize_imm(ctx, block, data_idx.to_int64())
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, memidx_vreg, data_idx_vreg, dst, src, size],
    None,
  )
}

///|
/// Lower data.drop instruction
/// data.drop marks a data segment as dropped
/// data_idx: data segment index
fn lower_data_drop(
  ctx : LoweringContext,
  _inst : @ir.Inst,
  block : @block.VCodeBlock,
  data_idx : Int,
) -> Unit {
  // Lower to a C call:
  //   wasmoon_jit_data_drop(vmctx, data_idx)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(DataDrop))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let data_idx_vreg = materialize_imm(ctx, block, data_idx.to_int64())
  lower_c_libcall(ctx, block, func_ptr_vreg, [vmctx_vreg, data_idx_vreg], None)
}
