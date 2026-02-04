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
