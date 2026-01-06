// NOTE: lower_table_get, lower_table_set, lower_table_size are removed
// These operations are desugared via FuncEnvironment at IR level to LoadPtr/StorePtr

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
  let result_vreg = match inst.first_result() {
    Some(result) => ctx.get_vreg(result)
    None => ctx.vcode_func.new_vreg(@abi.Int) // Create a temp vreg for the unused result
  }

  // Lower to a C call:
  //   wasmoon_jit_table_grow(vmctx, table_idx, delta, init_value) -> i32
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(TableGrow))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let table_idx_vreg = materialize_imm(ctx, block, table_idx.to_int64())
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, table_idx_vreg, delta, init_value],
    Some(result_vreg),
  )
}

///|
/// Lower table.fill instruction
/// table.fill fills a table region with a value
/// table_idx: table index
fn lower_table_fill(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  table_idx : Int,
) -> Unit {
  // Get the operands: dst, val, size
  guard inst.operands.length() >= 3 else { return }
  let dst = ctx.get_vreg_for_use(inst.operands[0], block)
  let val = ctx.get_vreg_for_use(inst.operands[1], block)
  let size = ctx.get_vreg_for_use(inst.operands[2], block)

  // Lower to a C call:
  //   wasmoon_jit_table_fill(vmctx, table_idx, dst, val, size)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(TableFill))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let table_idx_vreg = materialize_imm(ctx, block, table_idx.to_int64())
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, table_idx_vreg, dst, val, size],
    None,
  )
}

///|
/// Lower table.copy instruction
/// table.copy copies a table region (handles overlapping regions correctly)
/// dst_table_idx, src_table_idx: destination and source table indices
fn lower_table_copy(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  dst_table_idx : Int,
  src_table_idx : Int,
) -> Unit {
  // Get the operands: dst, src, size
  guard inst.operands.length() >= 3 else { return }
  let dst = ctx.get_vreg_for_use(inst.operands[0], block)
  let src = ctx.get_vreg_for_use(inst.operands[1], block)
  let size = ctx.get_vreg_for_use(inst.operands[2], block)

  // Lower to a C call:
  //   wasmoon_jit_table_copy(vmctx, dst_table_idx, src_table_idx, dst, src, size)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(TableCopy))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let dst_table_idx_vreg = materialize_imm(ctx, block, dst_table_idx.to_int64())
  let src_table_idx_vreg = materialize_imm(ctx, block, src_table_idx.to_int64())
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, dst_table_idx_vreg, src_table_idx_vreg, dst, src, size],
    None,
  )
}

///|
/// Lower table.init instruction
/// table.init copies elements from an element segment to a table
/// table_idx: table index, elem_idx: element segment index
fn lower_table_init(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  table_idx : Int,
  elem_idx : Int,
) -> Unit {
  // Get the operands: dst, src, size
  guard inst.operands.length() >= 3 else { return }
  let dst = ctx.get_vreg_for_use(inst.operands[0], block)
  let src = ctx.get_vreg_for_use(inst.operands[1], block)
  let size = ctx.get_vreg_for_use(inst.operands[2], block)

  // Lower to a C call:
  //   wasmoon_jit_table_init(vmctx, table_idx, elem_idx, dst, src, size)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(TableInit))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let table_idx_vreg = materialize_imm(ctx, block, table_idx.to_int64())
  let elem_idx_vreg = materialize_imm(ctx, block, elem_idx.to_int64())
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, table_idx_vreg, elem_idx_vreg, dst, src, size],
    None,
  )
}

///|
/// Lower elem.drop instruction
/// elem.drop marks an element segment as dropped
/// elem_idx: element segment index
fn lower_elem_drop(
  ctx : LoweringContext,
  _inst : @ir.Inst,
  block : @block.VCodeBlock,
  elem_idx : Int,
) -> Unit {
  // Lower to a C call:
  //   wasmoon_jit_elem_drop(vmctx, elem_idx)
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadJITFuncPtr(ElemDrop))
  load_ptr.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_ptr)
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  let elem_idx_vreg = materialize_imm(ctx, block, elem_idx.to_int64())
  lower_c_libcall(ctx, block, func_ptr_vreg, [vmctx_vreg, elem_idx_vreg], None)
}
