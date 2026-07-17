///|
/// Emit the legacy AMD64 epilogue.
fn MachineCode::emit_epilogue(
  self : MachineCode,
  stack_frame : EmitStackFrame,
) -> Unit {
  let isa = self.isa
  let saved_gprs = stack_frame.saved_gprs

  if self.debug_prev_func_idx_spill_offset >= 0 && stack_frame.needs_context_reg {
    let context = stack_frame.context_reg_index()
    let scratch = 11
    let layout = stack_frame.require_embedding_context_layout()
    self.x86_emit_mov_r32_m32(scratch, 4, self.debug_prev_func_idx_spill_offset)
    self.x86_emit_mov_m32_r32(
      context,
      layout.require_active_function_index_offset(),
      scratch,
    )
  }

  // Step 1: Deallocate remaining stack space (spill slots + outgoing args).
  let remaining_size = stack_frame.spill_size + stack_frame.outgoing_args_size
  if remaining_size > 0 {
    self.emit_sp_adjust(remaining_size)
  }

  // SysV has no callee-saved XMM regs.
  if stack_frame.saved_fprs.length() > 0 {
    abort("x86_64 epilogue: unexpected callee-saved fprs")
  }

  // Undo GPR-save padding.
  let gpr_padding = stack_frame.gpr_save_size - saved_gprs.length() * 8
  if gpr_padding > 0 {
    self.x86_emit_add_rsp_imm32(gpr_padding)
  }

  // Restore callee-saved GPRs (reverse order).
  let mut i = saved_gprs.length() - 1
  while i >= 0 {
    self.x86_emit_pop_r64(saved_gprs[i])
    i = i - 1
  }

  // Restore rbp and setup-area padding.
  if stack_frame.has_setup_area {
    if stack_frame.setup_area_size > 8 {
      self.x86_emit_add_rsp_imm32(stack_frame.setup_area_size - 8)
    }
    self.x86_emit_pop_r64(isa.fp_reg_index())
  }
}
