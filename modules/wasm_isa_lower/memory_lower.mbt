// Note: emit_bounds_check and emit_load_memory_base removed
// Memory bounds checking is now done at IR translation time via FuncEnvironment

///|
fn context_slot_offset(ctx : @lower.LoweringContext, slot_id : Int) -> Int {
  let layout = ctx.embedding_context_layout()
  match layout.slot_offset(slot_id) {
    Some(offset) => offset
    None => abort("missing Wasm context slot \{slot_id}")
  }
}

///|
pub fn load_context_slot_pointer(
  ctx : @lower.LoweringContext,
  block : @block.MachVBlock,
  slot_id : Int,
  base : @abi.Reg,
) -> @abi.VReg {
  let cache_key = context_slot_cache_key(slot_id)
  if ctx.cached_context_pointer(cache_key) is Some(vreg) {
    return vreg
  }
  let result = ctx.machv_function().new_vreg(Int)
  let load_inst = @instr.MachVInst::new(
    Load(I64, context_slot_offset(ctx, slot_id)),
  )
  load_inst.add_def({ reg: Virtual(result) })
  load_inst.add_use(base)
  block.add_inst(load_inst)
  ctx.cache_context_pointer(cache_key, result)
  result
}

///|
pub fn load_context_slot_pointer_from_pinned_context(
  ctx : @lower.LoweringContext,
  block : @block.MachVBlock,
  slot_id : Int,
) -> @abi.VReg {
  load_context_slot_pointer(
    ctx,
    block,
    slot_id,
    Physical({ index: @lower.context_index(ctx), class: Int }),
  )
}

///|
/// Emit instruction to load func_table from the Wasm context on-demand.
/// Returns a virtual register containing func_table pointer.
fn emit_load_func_table(
  ctx : @lower.LoweringContext,
  block : @block.MachVBlock,
) -> @abi.VReg {
  load_context_slot_pointer_from_pinned_context(
    ctx,
    block,
    CONTEXT_SLOT_FUNCTION_TABLE,
  )
}

///|
/// Lower GetFuncRef - get tagged function pointer for storing in tables
/// Returns func_ptr | FUNCREF_TAG (bit 61) for ref.test detection
pub fn lower_get_func_ref(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  func_idx : Int,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Step 1: Load func_table pointer from vmctx
  let func_table_vreg = emit_load_func_table(ctx, block)

  // Step 2: Load func_ptr from func_table[func_idx * 8]
  let raw_func_ptr = ctx.machv_function().new_vreg(Int)
  let offset = func_idx * 8
  if @lower.is_valid_load_store_offset(ctx, offset.to_int64(), 8) {
    let load_ptr = @instr.MachVInst::new(Load(I64, offset))
    load_ptr.add_def({ reg: Virtual(raw_func_ptr) })
    load_ptr.add_use(Virtual(func_table_vreg))
    block.add_inst(load_ptr)
  } else {
    // Large func-table indices exceed AArch64 LDR unsigned-imm range.
    let offset_vreg = @lower.materialize_imm(ctx, block, offset.to_int64())
    let load_ptr = @instr.MachVInst::new(LoadPtrRegOffset(I64, None, 0, 0))
    load_ptr.add_def({ reg: Virtual(raw_func_ptr) })
    load_ptr.add_use(Virtual(func_table_vreg))
    load_ptr.add_use(Virtual(offset_vreg))
    block.add_inst(load_ptr)
  }

  // Step 3: OR with FUNCREF_TAG (0x2000000000000000)
  let tag_vreg = ctx.machv_function().new_vreg(Int)
  let load_tag = @instr.MachVInst::new(LoadConst(0x2000000000000000L))
  load_tag.add_def({ reg: Virtual(tag_vreg) })
  block.add_inst(load_tag)
  let or_inst = @instr.MachVInst::new(Or(true))
  or_inst.add_def({ reg: Virtual(result_vreg) })
  or_inst.add_use(Virtual(raw_func_ptr))
  or_inst.add_use(Virtual(tag_vreg))
  block.add_inst(or_inst)
}

// Note: lower_load, lower_store, lower_load_narrow, lower_store_narrow removed
// Memory bounds checking is now done at IR translation time via FuncEnvironment
// MachV lowering now uses LoadPtr/StorePtr/LoadPtrNarrow/StorePtrNarrow directly

///|
/// Lower memory-base access to generic pointer loads from the runtime context.
/// memidx: memory index for multi-memory support
pub fn lower_load_mem_base(
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  memidx : Int,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  if inst.operands.length() != 1 {
    return
  }
  if ctx.cached_context_pointer(memidx) is Some(cached_vreg) {
    ctx.set_cached_vreg(result.id, cached_vreg)
    return
  }
  let result_vreg = ctx.get_vreg(result)
  let vmctx_reg : @abi.Reg = if ctx.abi_settings().enable_pinned_reg {
    Physical(@lower.context_preg(ctx))
  } else {
    let vmctx_vreg = ctx.get_vreg_for_use(inst.operands[0], block)
    Virtual(vmctx_vreg)
  }
  if memidx == 0 {
    ctx.machv_function().mark_uses_context_cache_0_source()
    let cached_vreg = load_context_slot_pointer(
      ctx,
      block,
      CONTEXT_SLOT_MEMORY0_BASE,
      vmctx_reg,
    )
    ctx.set_cached_vreg(result.id, cached_vreg)
    ctx.cache_context_pointer(memidx, cached_vreg)
    return
  } else {
    let directory_vreg = ctx.machv_function().new_vreg(Int)
    let load_directory = @instr.MachVInst::new(
      Load(I64, context_slot_offset(ctx, CONTEXT_SLOT_MEMORY_DIRECTORY)),
    )
    load_directory.add_def({ reg: Virtual(directory_vreg) })
    load_directory.add_use(vmctx_reg)
    block.add_inst(load_directory)

    let descriptor_vreg = ctx.machv_function().new_vreg(Int)
    let load_descriptor = @instr.MachVInst::new(
      Load(I64, memidx * WASM_CONTEXT_POINTER_STRIDE),
    )
    load_descriptor.add_def({ reg: Virtual(descriptor_vreg) })
    load_descriptor.add_use(Virtual(directory_vreg))
    block.add_inst(load_descriptor)

    let load_base = @instr.MachVInst::new(Load(I64, 0))
    load_base.add_def({ reg: Virtual(result_vreg) })
    load_base.add_use(Virtual(descriptor_vreg))
    block.add_inst(load_base)
  }
  ctx.cache_context_pointer(memidx, result_vreg)
}
