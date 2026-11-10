///|
pub fn depends_on_addresses(inst : @milkir.Inst) -> Bool {
  match inst.opcode {
    Ext(extension, _) =>
      extension.reads_address_epoch ||
      (extension.effects is Some(effects) && effects.pointer_region is Some(_))
    Memory(_) => true
    _ => false
  }
}

///|
pub fn invalidates_addresses(inst : @milkir.Inst) -> Bool {
  match inst.opcode {
    Ext(extension, _) if extension.effects is Some(effects) =>
      effects.invalidates_addresses
    _ => opcode_semantics(inst.opcode).memory is Unknown
  }
}

///|
fn collect_iconst_values(
  func : @milkir.Function,
  instructions : Array[@milkir.Inst],
) -> Array[Int64?] {
  let result : Array[Int64?] = Array::make(func.next_value_id, None)
  for inst in instructions {
    if inst.first_result() is Some(v) {
      match inst.opcode {
        Scalar(IntConst(value)) => result[v.id] = Some(value)
        Scalar(Copy) =>
          if inst.operands.length() > 0 &&
            result[inst.operands[0].id] is Some(copied) {
            result[v.id] = Some(copied)
          }
        _ => ()
      }
    }
  }
  result
}

///|
/// One flat use index over the active layout or the original budget prefix.
/// Links preserve use discovery order. Only operations that can propagate a
/// pointer fact have incoming links.
priv struct PointerUses {
  instructions : Array[@milkir.Inst]
  first_use : Array[Int32]
  users : Array[Int32]
  next_use : Array[Int32]
}

///|
fn PointerUses::new(
  func : @milkir.Function,
  instructions : Array[@milkir.Inst],
) -> PointerUses {
  let first_use = Array::make(func.next_value_id, -1)
  let last_use = Array::make(func.next_value_id, -1)
  let users : Array[Int32] = []
  let next_use : Array[Int32] = []
  for index, inst in instructions {
    if inst.results.is_empty() ||
      !(inst.opcode
      is Scalar(
        Copy
        | Convert(Bitcast | UnsignedExtend | SignedExtend | IntReduce)
        | IntBinary(Add | Sub)
        | Select
      )) {
      continue
    }
    for operand in inst.operands {
      let previous = last_use[operand.id]
      let edge = users.length()
      users.push(index)
      next_use.push(-1)
      if previous < 0 {
        first_use[operand.id] = edge
      } else {
        next_use[previous] = edge
      }
      last_use[operand.id] = edge
    }
  }
  { instructions, first_use, users, next_use, }
}

///|
fn active_pointer_instructions(func : @milkir.Function) -> Array[@milkir.Inst] {
  let instructions : Array[@milkir.Inst] = []
  for block in func.blocks {
    for id in func.block_instruction_ids(block) {
      instructions.push(func.instruction_by_id(id).unwrap())
    }
  }
  instructions
}

///|
pub fn pointer_regions(
  func : @milkir.Function,
  instructions? : Array[@milkir.Inst],
) -> Array[@milkir.AliasRegion?] {
  let instructions = match instructions {
    Some(source) => source
    None => active_pointer_instructions(func)
  }
  let uses = PointerUses::new(func, instructions)
  let constants = collect_iconst_values(func, instructions)
  infer_pointer_regions(func, uses, constants)
}

///|
fn infer_pointer_regions(
  func : @milkir.Function,
  uses : PointerUses,
  iconst_values : Array[Int64?],
) -> Array[@milkir.AliasRegion?] {
  let result : Array[@milkir.AliasRegion?] = Array::make(
    func.next_value_id,
    None,
  )
  for param in func.params {
    if param.1 is (Ptr | Ref | CallableRef | OpaqueRef) {
      result[param.0.id] = Some(Other)
    }
  }
  if func.blocks.length() > 0 {
    for param in func.blocks[0].params {
      if param.1 is (Ptr | Ref | CallableRef | OpaqueRef) {
        result[param.0.id] = Some(Other)
      }
    }
  }
  let worklist : Array[Int32] = []
  let queued = Array::make(func.next_inst_id, false)
  for inst in uses.instructions {
    queued[inst.id] = true
  }
  let initial_count = uses.instructions.length()
  let mut cursor = 0
  while cursor < initial_count + worklist.length() {
    let inst = uses.instructions[if cursor < initial_count {
        cursor
      } else {
        worklist[cursor - initial_count]
      }]
    cursor = cursor + 1
    queued[inst.id] = false
    if inst.first_result() is Some(v) && result[v.id] is None {
      let inferred : @milkir.AliasRegion? = match inst.opcode {
        GlobalValue(global_value) =>
          match func.global_value_data(global_value) {
            Some(ContextField(_, _, region)) => Some(region)
            None => None
          }
        Ext(extension, _) =>
          match extension.effects {
            Some(effects) => effects.pointer_region.map(region => region)
            None => None
          }
        Scalar(Copy)
        | Scalar(Convert(Bitcast))
        | Scalar(Convert(UnsignedExtend))
        | Scalar(Convert(SignedExtend))
        | Scalar(Convert(IntReduce)) =>
          if inst.operands.length() > 0 {
            result[inst.operands[0].id]
          } else {
            None
          }
        Scalar(IntBinary(Add)) =>
          if inst.operands.length() >= 2 {
            let lhs = inst.operands[0]
            let rhs = inst.operands[1]
            match (result[lhs.id], result[rhs.id]) {
              (Some(base), None) | (None, Some(base)) => Some(base)
              (Some(lhs_base), Some(rhs_base)) if lhs_base == rhs_base =>
                Some(lhs_base)
              _ =>
                if result[lhs.id] is Some(base) &&
                  is_known_iconst(rhs.id, iconst_values) {
                  Some(base)
                } else if result[rhs.id] is Some(base) &&
                  is_known_iconst(lhs.id, iconst_values) {
                  Some(base)
                } else {
                  None
                }
            }
          } else {
            None
          }
        Scalar(IntBinary(Sub)) =>
          if inst.operands.length() >= 2 {
            let lhs = inst.operands[0]
            let rhs = inst.operands[1]
            if result[lhs.id] is Some(base) &&
              is_known_iconst(rhs.id, iconst_values) {
              Some(base)
            } else {
              None
            }
          } else {
            None
          }
        Scalar(Select) =>
          if inst.operands.length() >= 3 &&
            result[inst.operands[1].id] is Some(lhs_base) &&
            result[inst.operands[2].id] is Some(rhs_base) &&
            lhs_base == rhs_base {
            Some(lhs_base)
          } else {
            None
          }
        _ => None
      }
      if inferred is Some(base) {
        result[v.id] = Some(base)
        let mut edge = uses.first_use[v.id]
        while edge >= 0 {
          let dependent = uses.users[edge]
          let id = uses.instructions[dependent].id
          if !queued[id] {
            worklist.push(dependent)
            queued[id] = true
          }
          edge = uses.next_use[edge]
        }
      }
    }
  }
  result
}

///|
fn is_known_iconst(value_id : Int32, iconst_values : Array[Int64?]) -> Bool {
  value_id >= 0 &&
  value_id < iconst_values.length() &&
  iconst_values[value_id] is Some(_)
}

///|
/// A raw store through a known pointer writes one exact region. A dialect
/// write also invalidates an unclassified read. Keep that distinction when
/// accumulating effects for a loop.
pub(all) enum RegionWrite {
  NoWrite
  AllRegions
  ExactRegion(@milkir.AliasRegion)
  RegionOrUnknownRead(@milkir.AliasRegion)
}

///|
pub fn region_write(
  inst : @milkir.Inst,
  pointers : Array[@milkir.AliasRegion?],
) -> RegionWrite {
  if inst.opcode is Ext(extension, _) && extension.effects is Some(effects) {
    return match effects.write {
      Some(Other) => AllRegions
      Some(written) => RegionOrUnknownRead(written)
      None => NoWrite
    }
  }
  if inst.opcode is Memory(Store(_) | StoreNarrow(_) | Vector(StoreLane(_, _))) &&
    inst.args.get(0) is Some(base) {
    return match pointers.get(base.id) {
      Some(Some(Other)) | Some(None) | None => AllRegions
      Some(Some(written)) => ExactRegion(written)
    }
  }
  if opcode_semantics(inst.opcode).memory.may_write_memory() {
    AllRegions
  } else {
    NoWrite
  }
}

///|
/// Bytes a checked producer guarantees can be read without a memory trap.
/// These facts do not extend physical lifetime: writes/calls still invalidate
/// the associated memory region before any read may move across them.
fn readable_pointer_bytes(
  func : @milkir.Function,
  uses : PointerUses,
) -> Array[Int32] {
  let bytes = Array::make(func.next_value_id, 0)
  let pending : Array[Int32] = []
  for inst in uses.instructions {
    if inst.results is [value] &&
      inst.opcode is Ext(extension, _) &&
      extension.effects is Some(effects) &&
      effects.pointer_bytes > 0 {
      bytes[value.id] = effects.pointer_bytes
      pending.push(value.id)
    }
  }
  let mut cursor = 0
  while cursor < pending.length() {
    let value = pending[cursor]
    cursor += 1
    let mut edge = uses.first_use[value]
    while edge >= 0 {
      let inst = uses.instructions[uses.users[edge]]
      if inst.opcode is Scalar(Copy | Convert(Bitcast)) &&
        inst.args.length() == 1 &&
        inst.results is [result] &&
        bytes[result.id] == 0 {
        bytes[result.id] = bytes[value]
        pending.push(result.id)
      }
      edge = uses.next_use[edge]
    }
  }
  bytes
}

///|
fn is_nontrapping_load(
  inst : @milkir.Inst,
  bytes : Array[Int32],
  constants : Array[Int64?],
) -> Bool {
  let width = match inst.opcode {
    Memory(Load(I32 | F32)) => 4
    Memory(Load(I64 | F64 | Ptr | Ref | CallableRef | OpaqueRef)) => 8
    Memory(Load(V128)) => 16
    Memory(LoadNarrow(_, bits, _)) => bits / 8
    _ => return false
  }
  guard inst.args is [base, offset] && bytes[base.id] >= width else {
    return false
  }
  // Dynamic/negative offsets do not inherit a bounded view's admission.
  match constants[offset.id] {
    Some(offset) =>
      offset >= 0L && offset <= (bytes[base.id] - width).to_int64()
    None => false
  }
}

///|
/// Compute the region and bounded-read facts over the same active definitions.
pub fn loop_pointer_facts(
  func : @milkir.Function,
) -> (Array[@milkir.AliasRegion?], Array[Bool]) {
  let instructions = active_pointer_instructions(func)
  let uses = PointerUses::new(func, instructions)
  let constants = collect_iconst_values(func, instructions)
  let regions = infer_pointer_regions(func, uses, constants)
  let bytes = readable_pointer_bytes(func, uses)
  let result = Array::make(func.next_inst_id, false)
  for inst in instructions {
    result[inst.id] = is_nontrapping_load(inst, bytes, constants)
  }
  (regions, result)
}
