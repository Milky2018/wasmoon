///|
fn opcode_debug_name(opcode : @machv.Opcode) -> String {
  match opcode {
    Target(name) => name
    _ => "machv." + to_repr(opcode).to_string()
  }
}

///|
pub suberror EmitError {
  UnsupportedOpcode(opcode~ : String)
  UnsupportedOperand(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for EmitError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn emit_u32_le(object : CodeObject, word : Int) -> Unit {
  object.code.push(word & 0xff)
  object.code.push((word >> 8) & 0xff)
  object.code.push((word >> 16) & 0xff)
  object.code.push((word >> 24) & 0xff)
}

///|
fn emit_x64_rex_w(object : CodeObject, r : Int, b : Int) -> Unit {
  object.code.push(0x48 | ((r & 1) << 2) | (b & 1))
}

///|
fn emit_x64_modrm(object : CodeObject, mod_ : Int, reg : Int, rm : Int) -> Unit {
  object.code.push(((mod_ & 3) << 6) | ((reg & 7) << 3) | (rm & 7))
}

///|
fn emit_x64_mov_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: mov r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x89)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_add_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: add r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x01)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn require_int_preg(
  operand : @machv.Operand,
  context : String,
) -> Int raise EmitError {
  match operand.reg {
    Physical(preg) =>
      if preg.class == Int && !preg.is_spilled() {
        preg.index
      } else {
        raise UnsupportedOperand(
          message="\{context} requires an integer physical register",
        )
      }
    Virtual(_) =>
      raise UnsupportedOperand(
        message="\{context} requires register allocation before emission",
      )
  }
}

///|
fn find_operand(
  inst : @machv.Instruction,
  role : @machv.OperandRole,
  index : Int,
  context : String,
) -> @machv.Operand raise EmitError {
  let mut seen = 0
  for operand in inst.operands {
    if operand.role == role {
      if seen == index {
        return operand
      }
      seen = seen + 1
    }
  }
  raise UnsupportedOperand(message="\{context} missing operand \{index}")
}

///|
fn emit_aarch64_move(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let src = require_int_preg(find_operand(inst, Use, 0, "mov"), "mov source")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "mov"),
    "mov destination",
  )
  // TODO(machv_emit): choose 32-bit or floating-register encodings from MachV value width.
  emit_u32_le(object, 0xaa0003e0 | (src << 16) | dst)
}

///|
fn emit_aarch64_int_add(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let lhs = require_int_preg(find_operand(inst, Use, 0, "add"), "add lhs")
  let rhs = require_int_preg(find_operand(inst, Use, 1, "add"), "add rhs")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "add"),
    "add destination",
  )
  // TODO(machv_emit): encode 32-bit integer adds and immediate forms once MachV carries lane width/legalization info.
  emit_u32_le(object, 0x8b000000 | (rhs << 16) | (lhs << 5) | dst)
}

///|
fn emit_x64_move(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let src = require_int_preg(find_operand(inst, Use, 0, "mov"), "mov source")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "mov"),
    "mov destination",
  )
  // TODO(machv_emit): choose 32-bit or floating-register encodings from MachV value width.
  emit_x64_mov_rr(object, dst, src)
}

///|
fn emit_x64_int_add(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let lhs = require_int_preg(find_operand(inst, Use, 0, "add"), "add lhs")
  let rhs = require_int_preg(find_operand(inst, Use, 1, "add"), "add rhs")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "add"),
    "add destination",
  )
  // TODO(machv_emit): replace this copy-first lowering with an X64 legalization pass that can pick two-address forms before emission.
  if dst != lhs {
    emit_x64_mov_rr(object, dst, lhs)
  }
  emit_x64_add_rr(object, dst, rhs)
}

///|
fn write_aarch64_inst_bytes(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  match inst.opcode {
    Move => emit_aarch64_move(object, inst)
    IntAdd => emit_aarch64_int_add(object, inst)
    Call(_) =>
      // TODO(machv_emit): resolve and range-check AArch64 BL relocations during real object linking.
      emit_u32_le(object, 0x94000000)
    Jump(_) =>
      // TODO(machv_emit): patch AArch64 B immediate once block layout is finalized.
      emit_u32_le(object, 0x14000000)
    Return => emit_u32_le(object, 0xd65f03c0)
    Trap(_) =>
      // TODO(machv_emit): encode trap reasons into target-specific debug/trap metadata.
      emit_u32_le(object, 0xd4200000)
    _ => raise UnsupportedOpcode(opcode=opcode_debug_name(inst.opcode))
  }
}

///|
fn write_x64_inst_bytes(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  match inst.opcode {
    Move => emit_x64_move(object, inst)
    IntAdd => emit_x64_int_add(object, inst)
    Call(_) => {
      // TODO(machv_emit): patch X64 call rel32 displacement during object linking.
      object.code.push(0xe8)
      emit_u32_le(object, 0)
    }
    Jump(_) => {
      // TODO(machv_emit): patch X64 jump rel32 displacement after block layout.
      object.code.push(0xe9)
      emit_u32_le(object, 0)
    }
    Return => object.code.push(0xc3)
    Trap(_) => {
      // TODO(machv_emit): encode trap reasons into target-specific debug/trap metadata.
      object.code.push(0xcc)
      object.code.push(0)
      object.code.push(0)
    }
    _ => raise UnsupportedOpcode(opcode=opcode_debug_name(inst.opcode))
  }
}

///|
fn write_inst_bytes(
  object : CodeObject,
  target : EmitTarget,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  match target {
    AArch64 => write_aarch64_inst_bytes(object, inst)
    X64 => write_x64_inst_bytes(object, inst)
  }
}

///|
fn record_relocations(
  object : CodeObject,
  offset : Int,
  opcode : @machv.Opcode,
) -> Unit {
  match opcode {
    Call(symbol) =>
      object.relocations.push({ offset, kind: ExternalSymbol(symbol) })
    Jump(target) => {
      object.relocations.push({ offset, kind: BlockTarget(target) })
      object.fixups.push({ offset, block_id: target })
    }
    Branch(true_target, false_target) => {
      object.relocations.push({ offset, kind: BlockTarget(true_target) })
      object.relocations.push({
        offset: offset + 1,
        kind: BlockTarget(false_target),
      })
      object.fixups.push({ offset, block_id: true_target })
      object.fixups.push({ offset: offset + 1, block_id: false_target })
    }
    _ => ()
  }
}

///|
fn record_stack_map(
  object : CodeObject,
  offset : Int,
  inst : @machv.Instruction,
) -> Unit {
  if inst.stack_effect != None {
    object.stack_maps.push({ offset, effect: inst.stack_effect })
  }
}

///|
fn emit_instruction(
  object : CodeObject,
  target : EmitTarget,
  block_id : Int,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let offset = object.current_offset()
  write_inst_bytes(object, target, inst)
  record_relocations(object, offset, inst.opcode)
  record_stack_map(object, offset, inst)
  object.debug_entries.push({
    offset,
    block_id,
    inst_id: inst.id,
    opcode: opcode_debug_name(inst.opcode),
  })
}

///|
pub fn emit_function_for_target(
  func : @machv.Function,
  target : EmitTarget,
) -> CodeObject raise EmitError {
  let object = CodeObject::new()
  for block in func.blocks {
    for inst in block.instructions {
      emit_instruction(object, target, block.id, inst)
    }
  }
  object
}

///|
pub fn emit_function(func : @machv.Function) -> CodeObject raise EmitError {
  // TODO(machv_emit): require callers to pass target metadata instead of relying on this temporary AArch64 default.
  emit_function_for_target(func, AArch64)
}
