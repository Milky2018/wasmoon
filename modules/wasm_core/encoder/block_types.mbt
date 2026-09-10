///|
/// Materialize text-only block signatures without mutating the input module.
fn resolve_block_types(module_ : @types.Module) -> @types.Module {
  let types = module_.types.copy()
  let groups = module_.type_rec_groups.copy()
  while groups.length() < types.length() {
    groups.push(groups.length())
  }
  let mut next_group = 0
  for group in groups {
    if group >= next_group {
      next_group = group + 1
    }
  }
  fn resolve(block : @types.BlockType) -> @types.BlockType {
    let (params, results) = match block {
      MultiValue(results) => ([], results)
      InlineType(params, results) => (params, results)
      _ => return block
    }
    for index, subtype in types {
      if subtype.composite is Func(function) &&
        function.params == params &&
        function.results == results {
        return TypeIndex(index)
      }
    }
    let index = types.length()
    types.push(@types.SubType::from_func({ params, results, }))
    groups.push(next_group)
    next_group = next_group + 1
    TypeIndex(index)
  }
  fn instructions(
    body : Array[@types.Instruction],
  ) -> Array[@types.Instruction] {
    body.map(fn(instruction) {
      match instruction {
        Block(signature, body) => Block(resolve(signature), instructions(body))
        Loop(signature, body) => Loop(resolve(signature), instructions(body))
        If(signature, yes, no) =>
          If(resolve(signature), instructions(yes), instructions(no))
        TryTable(signature, handlers, body) =>
          TryTable(resolve(signature), handlers, instructions(body))
        _ => instruction
      }
    })
  }
  let codes : Array[@types.FunctionCode] = module_.codes.map(fn(code) {
    { locals: code.locals, body: instructions(code.body), }
  })
  { ..module_, types, type_rec_groups: groups, codes, }
}
