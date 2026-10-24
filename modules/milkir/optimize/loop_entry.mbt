///|
/// Merge external header edges without executing any loop instruction. The
/// new block carries the original edge arguments, so guarded placement can
/// test the actual initial values and still bypass trapping reads on zero trips.
fn merge_loop_entries(
  function : @milkir.Function,
  cfg : @milkir.CFG,
  loop_ : @milkir.Loop,
) -> Bool {
  let entries = cfg
    .get_predecessors(loop_.header)
    .filter(id => !loop_.contains(id))
  if entries.is_empty() {
    return false
  }
  if entries is [single] &&
    find_unroll_block(function, single) is Some(block) &&
    block.terminator is Some(Jump(_, _)) {
    return false
  }
  let header = find_unroll_block(function, loop_.header).unwrap()
  let preheader = function.new_block0()
  let arguments = header.params.map(parameter => {
    function.append_block_param(preheader, parameter.1)
  })
  preheader.set_terminator(Jump(header.id, arguments))
  fn target(id : Int32) -> Int32 {
    if id == header.id {
      preheader.id
    } else {
      id
    }
  }
  for id in entries {
    let block = find_unroll_block(function, id).unwrap()
    let terminator : @milkir.Terminator = match block.terminator.unwrap() {
      Jump(next, arguments) => Jump(target(next), arguments)
      Branch(condition, a, aa, b, ba) =>
        Branch(condition, target(a), aa, target(b), ba)
      Brz(condition, a, b) => Brz(condition, target(a), target(b))
      Brnz(condition, a, b) => Brnz(condition, target(a), target(b))
      BrTable(index, targets, default_) =>
        BrTable(index, targets.map(target), target(default_))
      Return(_) | Trap(_) | TrapExit(_) => abort("invalid loop predecessor")
    }
    block.set_terminator(terminator)
  }
  true
}
