///|
/// Clone a region in layout order, remapping its definitions and edges.
/// Instruction replacements supply operands for the copy. Edges to blocks
/// outside the region keep their original targets unless explicitly redirected.
pub fn clone_region(
  function : @milkir.Function,
  body : Array[@milkir.Block],
  replace_instruction~ : (@milkir.Inst) -> (
    @milkir.Opcode,
    Array[@milkir.Value],
  )? = fn(_) { None },
  select_terminator~ : (@milkir.Block) -> @milkir.Terminator = fn(block) {
    block.terminator.unwrap()
  },
  redirect~ : (Int32) -> Int32? = fn(_) { None },
) -> Map[Int32, @milkir.Block] {
  let copies : Map[Int32, @milkir.Block] = Map([])
  let values : Map[Int32, @milkir.Value] = Map([])
  for block in body {
    let copy = function.new_block0()
    copies[block.id] = copy
    for (value, type_) in block.params {
      values[value.id] = function.append_block_param(copy, type_)
    }
    for id in function.block_instruction_ids(block) {
      for value in function.instruction_by_id(id).unwrap().results {
        values[value.id] = function.new_value(value.ty)
      }
    }
  }
  fn value(original : @milkir.Value) -> @milkir.Value {
    values.get(original.id).unwrap_or(original)
  }
  fn target(original : Int32) -> Int32 {
    match redirect(original) {
      Some(target) => target
      None => copies.get(original).map(block => block.id).unwrap_or(original)
    }
  }
  for block in body {
    let copy = copies[block.id]
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      let (opcode, args) = match replace_instruction(inst) {
        Some(replacement) => replacement
        None => (inst.opcode, inst.args.map(value))
      }
      let cloned = function.new_inst(opcode, args, inst.results.map(value))
      for metadata in inst.metadata {
        cloned.add_metadata(metadata)
      }
      copy.append_inst(cloned)
    }
    copy.set_terminator(
      remap_terminator(select_terminator(block), target, value~),
      metadata=block.terminator_metadata(),
    )
  }
  copies
}
