///|
fn edge_parallel_moves(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  block : @vcode.Block,
  successor_index : Int,
) -> Array[@vcode.ParallelMove] {
  let transfers : Array[@vcode.ParallelMove] = []
  for edit in allocation.edits() {
    match edit.kind() {
      EdgeMove(source~, successor_index=edge_index, value~, from~, to~) =>
        if source == block && edge_index == successor_index {
          transfers.push(
            @vcode.ParallelMove::new(
              function.value_type(value).unwrap(),
              from,
              to,
            ),
          )
        }
      _ => ()
    }
  }
  transfers
}

///|
fn resolve_edge_moves(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  block : @vcode.Block,
  successor_index : Int,
) -> Array[@vcode.ParallelMove] raise AArch64EmitError {
  @vcode.resolve_parallel_moves(
    edge_parallel_moves(function, allocation, block, successor_index),
    [@vcode.PhysicalReg::new(16, Int), @vcode.PhysicalReg::new(17, Int)],
    [
      @vcode.PhysicalReg::new(16, FpVector),
      @vcode.PhysicalReg::new(17, FpVector),
    ],
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
}

///|
fn emit_location_move(
  buffer : CodeBuffer,
  frame : AArch64Frame,
  transfer : @vcode.ParallelMove,
) -> Unit raise AArch64EmitError {
  match (transfer.from, transfer.to) {
    (Register(from), Register(to)) => emit_move(buffer, transfer.ty, to, from)
    (Stack(slot), Register(to)) =>
      emit_stack_access(
        buffer,
        true,
        transfer.ty,
        to,
        frame.slot_offset(slot).unwrap(),
      )
    (Register(from), Stack(slot)) =>
      emit_stack_access(
        buffer,
        false,
        transfer.ty,
        from,
        frame.slot_offset(slot).unwrap(),
      )
    (Stack(_), Stack(_)) => raise UnresolvedStackMove
  }
}

///|
fn emit_resolved_edge_moves(
  buffer : CodeBuffer,
  frame : AArch64Frame,
  transfers : Array[@vcode.ParallelMove],
) -> Unit raise AArch64EmitError {
  for transfer in transfers {
    emit_location_move(buffer, frame, transfer)
  }
}

///|
fn emit_edge_moves(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  block : @vcode.Block,
  successor_index : Int,
) -> Unit raise AArch64EmitError {
  emit_resolved_edge_moves(
    buffer,
    frame,
    resolve_edge_moves(function, allocation, block, successor_index),
  )
}

///|
fn emit_conditional_edges(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
  condition : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let when_true = function.instruction_successor_at(instruction, 0).unwrap().target
  let when_false = function.instruction_successor_at(instruction, 1).unwrap().target
  let true_moves = resolve_edge_moves(function, allocation, block, 0)
  let false_moves = resolve_edge_moves(function, allocation, block, 1)
  if true_moves.is_empty() {
    buffer.emit_branch(when_true, 19, 0x35000000U | reg_bits(condition))
    emit_resolved_edge_moves(buffer, frame, false_moves)
    buffer.emit_branch(when_false, 26, 0x14000000U)
  } else {
    let local_true_branch = buffer.position()
    buffer.emit_word(0x35000000U | reg_bits(condition))
    emit_resolved_edge_moves(buffer, frame, false_moves)
    buffer.emit_branch(when_false, 26, 0x14000000U)
    patch_relative_branch(buffer, local_true_branch, buffer.position(), 19)
    emit_resolved_edge_moves(buffer, frame, true_moves)
    buffer.emit_branch(when_true, 26, 0x14000000U)
  }
}
