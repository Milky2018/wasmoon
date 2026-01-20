///|
/// Exception Handling Lowering
/// Lowers IR exception opcodes to VCode instructions that call C runtime helpers

///|
/// Helper to get vmctx register as vreg
fn emit_load_vmctx(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
) -> @abi.VReg {
  let vmctx_vreg = ctx.vcode_func.new_vreg(Int)
  let vmctx_mov = @instr.VCodeInst::new(Move)
  vmctx_mov.add_def({ reg: Virtual(vmctx_vreg) })
  vmctx_mov.add_use(Physical({ index: @abi.REG_VMCTX, class: Int }))
  block.add_inst(vmctx_mov)
  vmctx_vreg
}

///|
/// Lower Throw(tag_idx) instruction
/// Calls exception_throw(ctx, tag_idx, values_ptr, count)
fn lower_throw(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  tag_idx : Int,
) -> Unit {
  // Get vmctx
  let vmctx_vreg = emit_load_vmctx(ctx, block)

  // Materialize tag index
  let tag_idx_vreg = materialize_imm(ctx, block, tag_idx.to_int64())

  // Allocate space for exception values (if any).
  //
  // Important: do NOT dynamically adjust SP here.
  // Our JIT assumes a fixed SP within the function body (after prologue), so
  // spills/stack slots use constant offsets from SP.
  //
  // Instead, reuse the pre-allocated outgoing-args area at SP and ensure it is
  // large enough for the values array.
  let num_operands = inst.operands.length()
  let (values_ptr_vreg, count_vreg) = if num_operands > 0 {
    let stack_space = (num_operands * 8 + 15) / 16 * 16
    ctx.vcode_func.update_max_outgoing_args_size(stack_space)

    // Store each value to the outgoing args area at SP.
    for i in 0..<num_operands {
      let val_vreg = ctx.get_vreg_for_use(inst.operands[i], block)
      let offset = i * 8
      let store = @instr.VCodeInst::new(StoreToStack(offset))
      store.add_use(Virtual(val_vreg))
      block.add_inst(store)
    }

    // Get current stack pointer as values_ptr
    let sp_vreg = ctx.vcode_func.new_vreg(Int)
    let load_sp = @instr.VCodeInst::new(LoadSP)
    load_sp.add_def({ reg: Virtual(sp_vreg) })
    block.add_inst(load_sp)
    (sp_vreg, materialize_imm(ctx, block, num_operands.to_int64()))
  } else {
    // No values - pass null and 0
    (materialize_imm(ctx, block, 0L), materialize_imm(ctx, block, 0L))
  }

  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(Throw))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // Call: exception_throw(ctx, tag_idx, values_ptr, count)
  // This is noreturn, but we still emit the call
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, tag_idx_vreg, values_ptr_vreg, count_vreg],
    None,
  )

  // Note: Stack cleanup not needed - throw is noreturn
}

///|
/// Lower ThrowRef instruction
/// Calls exception_throw_ref(ctx, exnref)
fn lower_throw_ref(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.operands.length() > 0 else { return }

  // Get vmctx
  let vmctx_vreg = emit_load_vmctx(ctx, block)

  // Get exnref from operand
  let exnref_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(ThrowRef))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // Call: exception_throw_ref(ctx, exnref)
  lower_c_libcall(ctx, block, func_ptr_vreg, [vmctx_vreg, exnref_vreg], None)
}

///|
/// Lower TryTableBegin(handler_id) instruction
/// Calls exception_try_begin(ctx, handler_id) -> jmp_buf ptr
/// Then calls sigsetjmp(jmp_buf_ptr, 0) -> result
///
/// The TryTableBegin IR instruction returns 0 normally, or handler_id on catch.
/// This is the result of sigsetjmp.
fn lower_try_table_begin(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  handler_id : Int,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)

  // Get vmctx
  let vmctx_vreg = emit_load_vmctx(ctx, block)

  // Materialize handler_id
  let handler_id_vreg = materialize_imm(ctx, block, handler_id.to_int64())

  // Load function pointer for try_begin
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(TryBegin))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // Call: exception_try_begin(ctx, handler_id) -> jmp_buf ptr
  let jmp_buf_ptr = ctx.vcode_func.new_vreg(Int)
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, handler_id_vreg],
    Some(jmp_buf_ptr),
  )

  // Now call sigsetjmp(jmp_buf_ptr, 0) to actually set the jump point
  // sigsetjmp returns 0 normally, or handler_id when longjmp is called
  //
  // Load sigsetjmp function pointer
  let setjmp_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_setjmp = @instr.VCodeInst::new(LoadExceptionFuncPtr(Sigsetjmp))
  load_setjmp.add_def({ reg: Virtual(setjmp_ptr_vreg) })
  block.add_inst(load_setjmp)

  // Second argument: savemask = 0 (don't save signal mask)
  let savemask_vreg = materialize_imm(ctx, block, 0L)

  // Call: sigsetjmp(jmp_buf_ptr, 0) -> result
  // Result is 0 on first call, handler_id on longjmp
  lower_c_libcall(
    ctx,
    block,
    setjmp_ptr_vreg,
    [jmp_buf_ptr, savemask_vreg],
    Some(dst),
  )
}

///|
/// Lower TryTableEnd(handler_id) instruction
/// Calls exception_try_end(ctx, handler_id)
fn lower_try_table_end(
  ctx : LoweringContext,
  _inst : @ir.Inst,
  block : @block.VCodeBlock,
  handler_id : Int,
) -> Unit {
  // Get vmctx
  let vmctx_vreg = emit_load_vmctx(ctx, block)

  // Materialize handler_id
  let handler_id_vreg = materialize_imm(ctx, block, handler_id.to_int64())

  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(TryEnd))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // Call: exception_try_end(ctx, handler_id)
  lower_c_libcall(
    ctx,
    block,
    func_ptr_vreg,
    [vmctx_vreg, handler_id_vreg],
    None,
  )
}

///|
/// Lower GetExceptionTag instruction
/// Calls exception_get_tag(ctx) -> tag
fn lower_get_exception_tag(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)

  // Get vmctx
  let vmctx_vreg = emit_load_vmctx(ctx, block)

  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(GetTag))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // Call: exception_get_tag(ctx) -> tag
  lower_c_libcall(ctx, block, func_ptr_vreg, [vmctx_vreg], Some(dst))
}

///|
/// Lower GetExceptionValue(idx) instruction
/// Calls exception_get_value(ctx, idx) -> value
fn lower_get_exception_value(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  idx : Int,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)

  // Get vmctx
  let vmctx_vreg = emit_load_vmctx(ctx, block)

  // Materialize index
  let idx_vreg = materialize_imm(ctx, block, idx.to_int64())

  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(GetValue))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // Call: exception_get_value(ctx, idx) -> value
  lower_c_libcall(ctx, block, func_ptr_vreg, [vmctx_vreg, idx_vreg], Some(dst))
}

///|
/// Lower GetExceptionValueCount instruction
/// Calls exception_get_value_count(ctx) -> count
fn lower_get_exception_value_count(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)

  // Get vmctx
  let vmctx_vreg = emit_load_vmctx(ctx, block)

  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(GetValueCount))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // Call: exception_get_value_count(ctx) -> count
  lower_c_libcall(ctx, block, func_ptr_vreg, [vmctx_vreg], Some(dst))
}

///|
/// Lower Delegate(depth) instruction
/// Calls exception_delegate(ctx, depth)
fn lower_delegate(
  ctx : LoweringContext,
  _inst : @ir.Inst,
  block : @block.VCodeBlock,
  depth : Int,
) -> Unit {
  // Get vmctx
  let vmctx_vreg = emit_load_vmctx(ctx, block)

  // Materialize depth
  let depth_vreg = materialize_imm(ctx, block, depth.to_int64())

  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(Delegate))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // Call: exception_delegate(ctx, depth)
  // This is noreturn
  lower_c_libcall(ctx, block, func_ptr_vreg, [vmctx_vreg, depth_vreg], None)
}

///|
/// Lower SpillLocalsForThrow(count) instruction
/// Calls exception_spill_locals(ctx, locals_ptr, count)
/// This saves all locals to memory so catch handlers can see throw-time values
fn lower_spill_locals_for_throw(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  count : Int,
) -> Unit {
  // Get vmctx
  let vmctx_vreg = emit_load_vmctx(ctx, block)

  // If no locals, pass null and 0
  let (locals_ptr_vreg, count_vreg) = if count > 0 {
    // Allocate stack space for locals (8 bytes each, aligned to 16)
    let stack_space = (count * 8 + 15) / 16 * 16
    let alloc = @instr.VCodeInst::new(AdjustSP(-stack_space))
    block.add_inst(alloc)

    // Store each local value to stack
    for i in 0..<count {
      let val_vreg = ctx.get_vreg_for_use(inst.operands[i], block)
      let offset = i * 8
      let store = @instr.VCodeInst::new(StoreToStack(offset))
      store.add_use(Virtual(val_vreg))
      block.add_inst(store)
    }

    // Get current stack pointer as locals_ptr
    let sp_vreg = ctx.vcode_func.new_vreg(Int)
    let load_sp = @instr.VCodeInst::new(LoadSP)
    load_sp.add_def({ reg: Virtual(sp_vreg) })
    block.add_inst(load_sp)

    // Materialize count
    let count_vreg = materialize_imm(ctx, block, count.to_int64())

    // Call spill_locals helper
    let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
    let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(SpillLocals))
    load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
    block.add_inst(load_fp)
    lower_c_libcall(
      ctx,
      block,
      func_ptr_vreg,
      [vmctx_vreg, sp_vreg, count_vreg],
      None,
    )

    // Clean up stack space
    let dealloc = @instr.VCodeInst::new(AdjustSP(stack_space))
    block.add_inst(dealloc)
    (sp_vreg, count_vreg)
  } else {
    // No locals - pass null and 0
    let null_vreg = materialize_imm(ctx, block, 0L)
    let zero_vreg = materialize_imm(ctx, block, 0L)

    // Still call spill_locals to clear any previous spilled state
    let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
    let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(SpillLocals))
    load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
    block.add_inst(load_fp)
    lower_c_libcall(
      ctx,
      block,
      func_ptr_vreg,
      [vmctx_vreg, null_vreg, zero_vreg],
      None,
    )
    (null_vreg, zero_vreg)
  }
  ignore((locals_ptr_vreg, count_vreg))
}

///|
/// Lower GetSpilledLocal(idx) instruction
/// Calls exception_get_spilled_local(ctx, idx) -> value
fn lower_get_spilled_local(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  idx : Int,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)

  // Get vmctx
  let vmctx_vreg = emit_load_vmctx(ctx, block)

  // Materialize index
  let idx_vreg = materialize_imm(ctx, block, idx.to_int64())

  // Load function pointer
  let func_ptr_vreg = ctx.vcode_func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadExceptionFuncPtr(GetSpilledLocal))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // Call: exception_get_spilled_local(ctx, idx) -> value
  lower_c_libcall(ctx, block, func_ptr_vreg, [vmctx_vreg, idx_vreg], Some(dst))
}
