///|
/// x86_64 VCode -> machine code emission (minimal subset).
///
/// This is Step 3 scaffolding: implement enough to validate the ABI plumbing
/// (prologue/epilogue, stack slots, simple arithmetic). The full backend will
/// be implemented incrementally.

///|
fn MachineCode::emit_instruction_x86_64(
  self : MachineCode,
  inst : @instr.VCodeInst,
  stack_frame : JITStackFrame,
) -> Unit {
  let spill_base_offset = stack_frame.spill_offset
  let frame_size = stack_frame.total_size
  let isa = @isa.ISA::current()
  fn cmp_kind_to_cond(kind : @instr.CmpKind) -> @instr.Cond {
    match kind {
      @instr.CmpKind::Eq => @instr.Cond::Eq
      @instr.CmpKind::Ne => @instr.Cond::Ne
      @instr.CmpKind::Slt => @instr.Cond::Lt
      @instr.CmpKind::Sle => @instr.Cond::Le
      @instr.CmpKind::Sgt => @instr.Cond::Gt
      @instr.CmpKind::Sge => @instr.Cond::Ge
      @instr.CmpKind::Ult => @instr.Cond::Lo
      @instr.CmpKind::Ule => @instr.Cond::Ls
      @instr.CmpKind::Ugt => @instr.Cond::Hi
      @instr.CmpKind::Uge => @instr.Cond::Hs
    }
  }

  match inst.opcode {
    @instr.Add(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // Expect the standard 2-operand lowering: rd == rn.
      if rd != rn {
        abort("x86_64 Add: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_add_rr(rd, rm)
      } else {
        self.x86_emit_add_rr32(rd, rm)
      }
    }
    @instr.Sub(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd != rn {
        abort("x86_64 Sub: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_sub_rr(rd, rm)
      } else {
        self.x86_emit_sub_rr32(rd, rm)
      }
    }
    @instr.AddImm(imm, is_64) => {
      // Fallback: materialize imm into scratch and use add/sub.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        abort("x86_64 AddImm: expected dst == lhs")
      }
      let scratch = isa.scratch_reg_1_index()
      self.x86_emit_mov_imm64(scratch, imm.to_int64())
      if is_64 {
        self.x86_emit_add_rr(rd, scratch)
      } else {
        self.x86_emit_add_rr32(rd, scratch)
      }
    }
    @instr.SubImm(imm, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        abort("x86_64 SubImm: expected dst == lhs")
      }
      let scratch = isa.scratch_reg_1_index()
      self.x86_emit_mov_imm64(scratch, imm.to_int64())
      if is_64 {
        self.x86_emit_sub_rr(rd, scratch)
      } else {
        self.x86_emit_sub_rr32(rd, scratch)
      }
    }
    @instr.Mul(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd != rn {
        abort("x86_64 Mul: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_imul_rr(rd, rm)
      } else {
        self.x86_emit_imul_rr32(rd, rm)
      }
    }
    @instr.And(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd != rn {
        abort("x86_64 And: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_and_rr(rd, rm)
      } else {
        self.x86_emit_and_rr32(rd, rm)
      }
    }
    @instr.Or(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd != rn {
        abort("x86_64 Or: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_or_rr(rd, rm)
      } else {
        self.x86_emit_or_rr32(rd, rm)
      }
    }
    @instr.Xor(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd != rn {
        abort("x86_64 Xor: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_xor_rr(rd, rm)
      } else {
        self.x86_emit_xor_rr32(rd, rm)
      }
    }
    @instr.Not(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        abort("x86_64 Not: expected dst == src")
      }
      if is_64 {
        self.x86_emit_not_r64(rd)
      } else {
        self.x86_emit_not_r32(rd)
      }
    }
    @instr.Move => {
      let rd = wreg_num(inst.defs[0])
      let rm = reg_num(inst.uses[0])
      if rd == rm {
        return
      }
      let reg_class = match inst.defs[0].reg {
        @abi.Physical(preg) => preg.class
        @abi.Virtual(_) => @abi.Int
      }
      match reg_class {
        @abi.Int => self.x86_emit_mov_rr(rd, rm)
        @abi.Float32 | @abi.Float64 | @abi.Vector =>
          self.x86_emit_movaps_xmm_xmm(rd, rm)
      }
    }
    @instr.LoadConst(v) => {
      let rd = wreg_num(inst.defs[0])
      self.x86_emit_mov_imm64(rd, v)
    }
    @instr.Cmp(kind, is_64) => {
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.x86_emit_cmp_rr(rn, rm)
      } else {
        self.x86_emit_cmp_rr32(rn, rm)
      }
      let rd = wreg_num(inst.defs[0])
      let cond = cmp_kind_to_cond(kind)
      self.x86_emit_setcc_r8(cond, rd)
      self.x86_emit_movzx_r32_r8(rd, rd)
    }
    @instr.Load(ty, offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if stack_frame.cache_func_table &&
        ty is @instr.MemType::I64 &&
        rn == vmctx_index() &&
        offset == @abi.VMCTX_FUNC_TABLE_OFFSET {
        let ft = func_table_index()
        if rt != ft {
          self.x86_emit_mov_rr(rt, ft)
        }
        return
      }
      match ty {
        @instr.MemType::I32 => self.x86_emit_mov_r32_m32(rt, rn, offset)
        @instr.MemType::I64 => self.x86_emit_mov_r64_m64(rt, rn, offset)
        @instr.MemType::F32 => self.x86_emit_movss_xmm_m32(rt, rn, offset)
        @instr.MemType::F64 => self.x86_emit_movsd_xmm_m64(rt, rn, offset)
        @instr.MemType::V128 => self.x86_emit_movdqu_xmm_m128(rt, rn, offset)
      }
    }
    @instr.Store(ty, offset) => {
      let rn = reg_num(inst.uses[0])
      let rt = reg_num(inst.uses[1])
      match ty {
        @instr.MemType::I32 => self.x86_emit_mov_m32_r32(rn, offset, rt)
        @instr.MemType::I64 => self.x86_emit_mov_m64_r64(rn, offset, rt)
        @instr.MemType::F32 => self.x86_emit_movss_m32_xmm(rn, offset, rt)
        @instr.MemType::F64 => self.x86_emit_movsd_m64_xmm(rn, offset, rt)
        @instr.MemType::V128 => self.x86_emit_movdqu_m128_xmm(rn, offset, rt)
      }
    }
    @instr.Load8S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movsx_r64_m8(rt, rn, offset)
    }
    @instr.Load8U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movzx_r32_m8(rt, rn, offset)
    }
    @instr.Load16S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movsx_r64_m16(rt, rn, offset)
    }
    @instr.Load16U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movzx_r32_m16(rt, rn, offset)
    }
    @instr.Load32S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movsxd_r64_m32(rt, rn, offset)
    }
    @instr.Load32U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_mov_r32_m32(rt, rn, offset)
    }
    @instr.LoadFuncAddr(func_idx) => {
      // Load function pointer from vmctx->func_table[func_idx].
      let rd = wreg_num(inst.defs[0])
      let vmctx = vmctx_index()
      let table = isa.scratch_reg_1_index()
      self.x86_emit_mov_r64_m64(table, vmctx, @abi.VMCTX_FUNC_TABLE_OFFSET)
      self.x86_emit_mov_r64_m64(rd, table, func_idx * 8)
    }
    @instr.CallDirect(func_idx, _num_args, _num_results, _call_conv) => {
      // Call via vmctx->func_table[func_idx] to avoid rel32 patching.
      let vmctx = vmctx_index()
      let table = isa.scratch_reg_1_index()
      let callee = isa.scratch_reg_2_index()
      self.x86_emit_mov_r64_m64(table, vmctx, @abi.VMCTX_FUNC_TABLE_OFFSET)
      self.x86_emit_mov_r64_m64(callee, table, func_idx * 8)
      self.x86_emit_call_r64(callee)
    }
    @instr.CallPtr(_, _, _call_conv) => {
      // Standard call: arguments already placed by lowering.
      let target = match inst.use_constraints[0] {
        @abi.FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[0])
      }
      self.x86_emit_call_r64(target)
    }
    @instr.AdjustSP(delta) =>
      if delta > 0 {
        self.x86_emit_add_rsp_imm32(delta)
      } else if delta < 0 {
        self.x86_emit_sub_rsp_imm32(-delta)
      }
    @instr.StoreToStack(offset) => {
      // Store to pre-allocated outgoing args area at [rsp + outgoing_args_offset + offset].
      let actual_offset = stack_frame.outgoing_args_offset + offset
      let src = reg_num(inst.uses[0])
      let src_class = match inst.uses[0] {
        @abi.Physical(preg) => preg.class
        @abi.Virtual(vreg) => vreg.class
      }
      match src_class {
        @abi.Int => self.x86_emit_mov_m64_r64(4, actual_offset, src)
        @abi.Float32 | @abi.Float64 =>
          self.x86_emit_movsd_m64_xmm(4, actual_offset, src)
        @abi.Vector => self.x86_emit_movdqu_m128_xmm(4, actual_offset, src)
      }
    }
    @instr.LoadSP => {
      let rd = wreg_num(inst.defs[0])
      self.x86_emit_mov_rr(rd, 4)
    }
    @instr.StackLoad(offset) => {
      let rd = wreg_num(inst.defs[0])
      let def_class = match inst.defs[0].reg {
        @abi.Physical(preg) => preg.class
        @abi.Virtual(vreg) => vreg.class
      }
      let disp = spill_base_offset + offset
      match def_class {
        @abi.Int => self.x86_emit_mov_r64_m64(rd, 4, disp)
        @abi.Float32 | @abi.Float64 => self.x86_emit_movsd_xmm_m64(rd, 4, disp)
        @abi.Vector => self.x86_emit_movdqu_xmm_m128(rd, 4, disp)
      }
    }
    @instr.StackStore(offset) => {
      let rt = reg_num(inst.uses[0])
      let use_class = match inst.uses[0] {
        @abi.Physical(preg) => preg.class
        @abi.Virtual(vreg) => vreg.class
      }
      let disp = spill_base_offset + offset
      match use_class {
        @abi.Int => self.x86_emit_mov_m64_r64(4, disp, rt)
        @abi.Float32 | @abi.Float64 => self.x86_emit_movsd_m64_xmm(4, disp, rt)
        @abi.Vector => self.x86_emit_movdqu_m128_xmm(4, disp, rt)
      }
    }
    @instr.LoadStackParam(offset, class) => {
      // Load from [entry_sp + offset] where entry_sp = rsp + total_size.
      let rd = wreg_num(inst.defs[0])
      let disp = frame_size + offset
      match class {
        @abi.Int => self.x86_emit_mov_r64_m64(rd, 4, disp)
        @abi.Float32 | @abi.Float64 => self.x86_emit_movsd_xmm_m64(rd, 4, disp)
        @abi.Vector => self.x86_emit_movdqu_xmm_m128(rd, 4, disp)
      }
    }
    _ => abort("x86_64 opcode not implemented: \{inst.opcode}")
  }
}
