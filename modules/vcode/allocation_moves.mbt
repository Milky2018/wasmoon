///|
pub fn[Inst] allocation_edit_moves(
  function : Function[Inst],
  allocation : Allocation,
  instruction : Instruction,
  placement : PointPlacement,
) -> Array[ParallelMove] {
  let moves : Array[ParallelMove] = []
  for edit in allocation.edits_at(instruction, placement) {
    match edit.kind() {
      Spill(value~, reg~, slot~) =>
        moves.push(
          ParallelMove::new(
            function.value_type(value).unwrap(),
            Register(reg),
            Stack(slot),
          ),
        )
      Reload(value~, slot~, reg~) =>
        moves.push(
          ParallelMove::new(
            function.value_type(value).unwrap(),
            Stack(slot),
            Register(reg),
          ),
        )
      Move(value~, from~, to~) =>
        moves.push(
          ParallelMove::new(
            function.value_type(value).unwrap(),
            Register(from),
            Register(to),
          ),
        )
      EdgeMove(..) => ()
    }
  }
  moves
}

///|
pub fn[Inst] allocation_edge_moves(
  function : Function[Inst],
  allocation : Allocation,
  block : Block,
  successor_index : Int32,
) -> Array[ParallelMove] {
  let transfers : Array[ParallelMove] = []
  for edit in allocation.edge_edits_at(block, successor_index) {
    match edit.kind() {
      EdgeMove(value~, from~, to~, ..) =>
        transfers.push(
          ParallelMove::new(function.value_type(value).unwrap(), from, to),
        )
      _ => ()
    }
  }
  transfers
}
