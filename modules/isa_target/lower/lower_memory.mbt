///|
/// Emit instruction to load table0_base from vmctx on-demand (Standard)
/// Returns a virtual register containing table0_base pointer
/// This is called before indirect calls to get the indirect table base address
pub fn emit_load_table0_base(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
) -> @abi.VReg {
  if ctx.table0_base_cache.get(block.id) is Some(vreg) {
    return vreg
  }
  let layout = ctx.require_runtime_layout()
  let table0_base_vreg = ctx.vcode_func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(
    Load(I64, layout.primary_table_base_offset),
  )
  load_inst.add_def({ reg: Virtual(table0_base_vreg) })
  load_inst.add_use(Physical({ index: vmctx_index(ctx), class: Int })) // vmctx
  block.add_inst(load_inst)
  ctx.table0_base_cache.set(block.id, table0_base_vreg)
  table0_base_vreg
}
