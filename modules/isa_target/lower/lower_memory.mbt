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
  let layout = ctx.require_runtime_layout()
  let func_table_vreg = ctx.vcode_func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(Load(I64, layout.function_table_offset))
  load_inst.add_def({ reg: Virtual(func_table_vreg) })
  load_inst.add_use(Physical({ index: vmctx_index(ctx), class: Int })) // vmctx
  block.add_inst(load_inst)
  ctx.func_table_cache.set(block.id, func_table_vreg)
  func_table_vreg
}

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

///|
/// Lower GetFuncRef - get tagged function pointer for storing in tables
/// Returns func_ptr | FUNCREF_TAG (bit 61) for ref.test detection
pub fn lower_get_func_ref(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.VCodeBlock,
  func_idx : Int,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Step 1: Load func_table pointer from vmctx
  let func_table_vreg = emit_load_func_table(ctx, block)

  // Step 2: Load func_ptr from func_table[func_idx * 8]
  let raw_func_ptr = ctx.vcode_func.new_vreg(Int)
  let offset = func_idx * 8
  if is_valid_load_store_offset(ctx, offset.to_int64(), 8) {
    let load_ptr = @instr.VCodeInst::new(Load(I64, offset))
    load_ptr.add_def({ reg: Virtual(raw_func_ptr) })
    load_ptr.add_use(Virtual(func_table_vreg))
    block.add_inst(load_ptr)
  } else {
    // Large func-table indices exceed AArch64 LDR unsigned-imm range.
    let offset_vreg = materialize_imm(ctx, block, offset.to_int64())
    let load_ptr = @instr.VCodeInst::new(LoadPtrRegOffset(I64, None, 0, 0))
    load_ptr.add_def({ reg: Virtual(raw_func_ptr) })
    load_ptr.add_use(Virtual(func_table_vreg))
    load_ptr.add_use(Virtual(offset_vreg))
    block.add_inst(load_ptr)
  }

  // Step 3: OR with FUNCREF_TAG (0x2000000000000000)
  let tag_vreg = ctx.vcode_func.new_vreg(Int)
  let load_tag = @instr.VCodeInst::new(LoadConst(0x2000000000000000L))
  load_tag.add_def({ reg: Virtual(tag_vreg) })
  block.add_inst(load_tag)
  let or_inst = @instr.VCodeInst::new(Or(true))
  or_inst.add_def({ reg: Virtual(result_vreg) })
  or_inst.add_use(Virtual(raw_func_ptr))
  or_inst.add_use(Virtual(tag_vreg))
  block.add_inst(or_inst)
}

// Note: lower_load, lower_store, lower_load_narrow, lower_store_narrow removed
// Memory bounds checking is now done at IR translation time via FuncEnvironment
// VCode lowering now uses LoadPtr/StorePtr/LoadPtrNarrow/StorePtrNarrow directly

///|
/// Lower memory-base access to generic pointer loads from the runtime context.
/// memidx: memory index for multi-memory support
pub fn lower_load_mem_base(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.VCodeBlock,
  memidx : Int,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  if inst.operands.length() != 1 {
    return
  }
  if ctx.mem_base_cache.get(memidx) is Some(cached_vreg) {
    ctx.set_cached_vreg(result.id, cached_vreg)
    return
  }
  let result_vreg = ctx.get_vreg(result)
  let vmctx_reg : @abi.Reg = if ctx.abi_settings.enable_pinned_reg {
    Physical(vmctx_preg(ctx))
  } else {
    let vmctx_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
    Virtual(vmctx_vreg)
  }
  let layout = ctx.require_runtime_layout()
  if memidx == 0 {
    ctx.vcode_func.mark_uses_primary_memory_base()
    let load_base = @instr.VCodeInst::new(
      Load(I64, layout.primary_memory_base_offset),
    )
    load_base.add_def({ reg: Virtual(result_vreg) })
    load_base.add_use(vmctx_reg)
    block.add_inst(load_base)
  } else {
    let directory_vreg = ctx.vcode_func.new_vreg(Int)
    let load_directory = @instr.VCodeInst::new(
      Load(I64, layout.memory_directory_offset),
    )
    load_directory.add_def({ reg: Virtual(directory_vreg) })
    load_directory.add_use(vmctx_reg)
    block.add_inst(load_directory)

    let descriptor_vreg = ctx.vcode_func.new_vreg(Int)
    let load_descriptor = @instr.VCodeInst::new(
      Load(I64, memidx * layout.pointer_stride),
    )
    load_descriptor.add_def({ reg: Virtual(descriptor_vreg) })
    load_descriptor.add_use(Virtual(directory_vreg))
    block.add_inst(load_descriptor)

    let load_base = @instr.VCodeInst::new(Load(I64, 0))
    load_base.add_def({ reg: Virtual(result_vreg) })
    load_base.add_use(Virtual(descriptor_vreg))
    block.add_inst(load_base)
  }
  ctx.mem_base_cache.set(memidx, result_vreg)
}
