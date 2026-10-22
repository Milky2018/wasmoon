///|
priv struct GcRead {
  object : Int32
  type_index : Int32
  field_index : Int32
  mode : Int32
} derive(Eq, Hash)

///|
fn canonical_value(
  function : @milkir.Function,
  value : @milkir.Value,
) -> @milkir.Value {
  let mut current = value
  // This is an opportunistic pass; long copy chains need not be canonical.
  for _ in 0..<64 {
    guard function.defining_inst(current) is Some(inst) &&
      inst.opcode is Scalar(Copy) &&
      inst.args.length() == 1 else {
      break
    }
    current = inst.args[0]
  }
  current
}

///|
fn remember_read(
  cache : Map[GcRead, @milkir.Value],
  key : GcRead,
  value : @milkir.Value,
) -> Unit {
  // Bound fact copying and alias invalidation for large, untrusted functions.
  // Forgetting a fact only forgoes an optimization; it never removes a read.
  if cache.length() >= 128 {
    cache.clear()
  }
  cache[key] = value
}

///|
fn forward_gc_reads(function : @milkir.Function) -> Int32 {
  let cfg = @milkir.CFG::build(function)
  let blocks : Map[Int32, @milkir.Block] = Map([])
  let outgoing : Map[Int32, Map[GcRead, @milkir.Value]] = Map([])
  for block in function.blocks {
    blocks[block.id] = block
  }
  let mut changed = 0
  for block_id in cfg.reverse_postorder() {
    let block = blocks[block_id]
    let cache : Map[GcRead, @milkir.Value] = Map([])
    // A single forward predecessor forms an extended basic block. Merges
    // and backedges start with no facts; reads are never hoisted.
    if cfg.get_predecessors(block_id) is [previous] &&
      outgoing.get(previous) is Some(inherited) {
      for key, value in inherited {
        cache[key] = value
      }
    }
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      let operation = @wasm_milkir.decode_opcode(inst.opcode)
      let read = match operation {
        Some(StructGet(type_index, field_index)) =>
          Some((type_index, field_index, 0))
        Some(StructGetS(type_index, field_index, width)) =>
          Some((type_index, field_index, width * 4 + 1))
        Some(StructGetU(type_index, field_index, width)) =>
          Some((type_index, field_index, width * 4 + 2))
        Some(ArrayLen) => Some((-1, -1, 0))
        _ => None
      }
      if read is Some((type_index, field_index, mode)) &&
        inst.args.length() == 1 &&
        inst.results is [result] {
        let key = {
          object: canonical_value(function, inst.args[0]).id,
          type_index,
          field_index,
          mode,
        }
        if cache.get(key) is Some(value) && value.ty == result.ty {
          inst.args.clear()
          inst.args.push(canonical_value(function, value))
          inst.set_opcode(Scalar(Copy))
          changed += 1
        } else {
          remember_read(cache, key, result)
        }
        continue
      }
      match operation {
        Some(StructSet(type_index, field_index)) => {
          // Distinct SSA values or indexed types can alias one object. Kill
          // this field for every object/type before forwarding the write.
          for key in cache.keys().to_array() {
            if key.field_index == field_index {
              cache.remove(key)
            }
          }
          if inst.args.length() == 2 {
            remember_read(
              cache,
              {
                object: canonical_value(function, inst.args[0]).id,
                type_index,
                field_index,
                mode: 0,
              },
              canonical_value(function, inst.args[1]),
            )
          }
        }
        // Arrays cannot resize and their payload cannot alias struct fields.
        Some(
          ArraySet(_)
          | ArrayFill(_)
          | ArrayCopy(_, _)
          | ArrayInitData(_, _)
          | ArrayInitElem(_, _)
          | ArrayGet(_)
          | ArrayGetS(_, _)
          | ArrayGetU(_, _)
          | I31New
          | I31GetS
          | I31GetU
        ) => ()
        _ =>
          match inst.opcode {
            Scalar(_) | GlobalValue(_) | Vector(_) => ()
            Memory(Load(_) | LoadNarrow(_, _, _)) => ()
            _ => cache.clear()
          }
      }
    }
    outgoing[block_id] = cache
  }
  changed
}
