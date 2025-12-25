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
