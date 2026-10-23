///|
fn collect_iconst_values(
  func : @milkir.Function,
  instructions? : Array[@milkir.Inst],
) -> Array[Int64?] {
  let result : Array[Int64?] = Array::make(func.next_value_id, None)
  let record = fn(inst : @milkir.Inst) {
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
  match instructions {
    Some(prefix) =>
      for inst in prefix {
        record(inst)
      }
    None =>
      for block in func.blocks {
        for inst_id in block.instruction_ids() {
          record(func.instruction_by_id(inst_id).unwrap())
        }
      }
  }
  result
}

///|
pub fn pointer_regions(
  func : @milkir.Function,
  instructions? : Array[@milkir.Inst],
) -> Array[@milkir.AliasRegion?] {
  let iconst_values = collect_iconst_values(func, instructions?)
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
  let dependents : Array[Array[@milkir.Inst]] = Array::makei(
    func.next_value_id,
    _ => [],
  )
  let worklist : Array[@milkir.Inst] = []
  let queued = Array::make(func.next_inst_id, false)
  let enqueue = fn(inst : @milkir.Inst) {
    worklist.push(inst)
    queued[inst.id] = true
    for operand in inst.operands {
      dependents[operand.id].push(inst)
    }
  }
  match instructions {
    Some(prefix) =>
      for inst in prefix {
        enqueue(inst)
      }
    None =>
      for block in func.blocks {
        for inst_id in block.instruction_ids() {
          enqueue(func.instruction_by_id(inst_id).unwrap())
        }
      }
  }
  let mut cursor = 0
  while cursor < worklist.length() {
    let inst = worklist[cursor]
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
        for dependent in dependents[v.id] {
          if !queued[dependent.id] {
            worklist.push(dependent)
            queued[dependent.id] = true
          }
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
/// Whether this instruction can invalidate a read in the requested region.
/// Unknown stores and calls include metadata and all payload regions.
pub fn may_write_region(
  inst : @milkir.Inst,
  pointers : Array[@milkir.AliasRegion?],
  region : @milkir.AliasRegion,
) -> Bool {
  if inst.opcode is Ext(extension, _) && extension.effects is Some(effects) {
    return match effects.write {
      Some(Other) => true
      Some(written) => region == Other || written == region
      None => false
    }
  }
  if inst.opcode is Memory(Store(_) | StoreNarrow(_) | Vector(StoreLane(_, _))) &&
    inst.args.get(0) is Some(base) {
    return match pointers.get(base.id) {
      Some(Some(Other)) | Some(None) | None => true
      Some(Some(written)) => written == region
    }
  }
  opcode_semantics(inst.opcode).memory.may_write_memory()
}

///|
/// Bytes a checked producer guarantees can be read without a memory trap.
/// These facts do not extend physical lifetime: writes/calls still invalidate
/// the associated memory region before any read may move across them.
fn readable_pointer_bytes(func : @milkir.Function) -> Array[Int32] {
  let bytes = Array::make(func.next_value_id, 0)
  let mut changed = true
  while changed {
    changed = false
    for block in func.blocks {
      for id in func.block_instruction_ids(block) {
        let inst = func.instruction_by_id(id).unwrap()
        if inst.results is [value] && bytes[value.id] == 0 {
          let count = match inst.opcode {
            Ext(extension, _) =>
              match extension.effects {
                Some(effects) => effects.pointer_bytes
                None => 0
              }
            Scalar(Copy | Convert(Bitcast)) =>
              if inst.args is [source] {
                bytes[source.id]
              } else {
                0
              }
            _ => 0
          }
          if count > 0 {
            bytes[value.id] = count
            changed = true
          }
        }
      }
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
pub fn nontrapping_loads(func : @milkir.Function) -> Array[Bool] {
  let bytes = readable_pointer_bytes(func)
  let constants = collect_iconst_values(func)
  let result = Array::make(func.next_inst_id, false)
  for block in func.blocks {
    for id in func.block_instruction_ids(block) {
      result[id] = is_nontrapping_load(
        func.instruction_by_id(id).unwrap(),
        bytes,
        constants,
      )
    }
  }
  result
}
