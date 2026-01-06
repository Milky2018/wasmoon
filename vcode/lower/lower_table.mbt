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
