///|
fn opcode_debug_name(opcode : @machv.Opcode) -> String {
  match opcode {
    Target(name) => name
    _ => "machv." + to_repr(opcode).to_string()
  }
}

///|
fn opcode_tag(opcode : @machv.Opcode) -> Int {
  match opcode {
    Target(_) => 0x10
    Load(_) => 0x30
    Store(_) => 0x31
    Call(_) => 0x40
    Trap(_) => 0x41
    Jump(_) => 0x50
    Branch(_) => 0x51
    Return => 0x60
    _ => 0x20
  }
}

///|
fn operand_tag(operand : @machv.Operand) -> Int {
  match operand.reg {
    Virtual(vreg) => vreg.id
    Physical(preg) => 0x80 + preg.index
  }
}

///|
fn write_inst_bytes(object : CodeObject, inst : @machv.Instruction) -> Unit {
  object.code.push(opcode_tag(inst.opcode))
  object.code.push(inst.operands.length())
  for operand in inst.operands {
    object.code.push(operand_tag(operand))
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
  block_id : Int,
  inst : @machv.Instruction,
) -> Unit {
  let offset = object.current_offset()
  write_inst_bytes(object, inst)
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
pub fn emit_function(func : @machv.Function) -> CodeObject {
  let object = CodeObject::new()
  // TODO(machv_emit): replace pseudo instruction bytes with ISA-specific
  // binary encoders while keeping relocation and metadata records generic.
  for block in func.blocks {
    for inst in block.instructions {
      emit_instruction(object, block.id, inst)
    }
  }
  object
}
