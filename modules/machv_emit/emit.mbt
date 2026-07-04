///|
fn opcode_debug_name(opcode : @machv.Opcode) -> String {
  match opcode {
    Target(name) => name
    Move => "machv.move"
    IntConst(value) => "machv.iconst." + value.to_string()
    FloatConst(value) => "machv.fconst." + value.to_string()
    IntAdd => "machv.iadd"
    IntSub => "machv.isub"
    IntMul => "machv.imul"
    IntCmp(cond) => "machv.icmp." + to_repr(cond).to_string()
    FloatAdd => "machv.fadd"
    FloatSub => "machv.fsub"
    FloatMul => "machv.fmul"
    Select => "machv.select"
    Load(slot) => "machv.load.slot." + slot.id.to_string()
    Store(slot) => "machv.store.slot." + slot.id.to_string()
    Call(symbol) => "machv.call." + symbol
    Trap(reason) => "machv.trap." + reason
    Jump(target) => "machv.jump." + target.to_string()
    Branch(true_target, false_target) =>
      "machv.branch." + true_target.to_string() + "." + false_target.to_string()
    Return => "machv.return"
  }
}

///|
fn opcode_tag(opcode : @machv.Opcode) -> Int {
  match opcode {
    Target(_) => 0x10
    Move => 0x20
    IntConst(_) => 0x21
    FloatConst(_) => 0x22
    IntAdd => 0x23
    IntSub => 0x24
    IntMul => 0x25
    IntCmp(_) => 0x26
    FloatAdd => 0x27
    FloatSub => 0x28
    FloatMul => 0x29
    Select => 0x2a
    Load(_) => 0x30
    Store(_) => 0x31
    Call(_) => 0x40
    Trap(_) => 0x41
    Jump(_) => 0x50
    Branch(_) => 0x51
    Return => 0x60
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
    Target(_)
    | Move
    | IntConst(_)
    | FloatConst(_)
    | IntAdd
    | IntSub
    | IntMul
    | IntCmp(_)
    | FloatAdd
    | FloatSub
    | FloatMul
    | Select
    | Load(_)
    | Store(_)
    | Trap(_)
    | Return => ()
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
