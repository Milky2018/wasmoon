///|
fn edge_parallel_moves(
  function : @vcode.Function[X64Inst],
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
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  block : @vcode.Block,
  successor_index : Int,
) -> @vcode.ResolvedMovePlan raise X64EmitError {
  @vcode.plan_parallel_moves(
    edge_parallel_moves(function, allocation, block, successor_index),
    int_transfer_scratch(),
    fp_transfer_scratch(),
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
}

///|
fn emit_location_move(
  buffer : CodeBuffer,
  frame : X64Frame,
  transfer : @vcode.ParallelMove,
) -> Unit raise X64EmitError {
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
fn emit_resolved_moves(
  buffer : CodeBuffer,
  frame : X64Frame,
  plan : @vcode.ResolvedMovePlan,
) -> Unit raise X64EmitError {
  for step in plan.steps {
    match step {
      Transfer(transfer) => emit_location_move(buffer, frame, transfer)
      SpillScratchToEmergency(ty~, scratch~) => {
        guard frame.emergency_move_offset() is Some(offset) else {
          raise MissingEmergencyMoveArea
        }
        emit_stack_access(buffer, false, ty, scratch, offset)
      }
      ReloadScratchFromEmergency(ty~, scratch~) => {
        guard frame.emergency_move_offset() is Some(offset) else {
          raise MissingEmergencyMoveArea
        }
        emit_stack_access(buffer, true, ty, scratch, offset)
      }
    }
  }
}

///|
fn emit_edge_moves(
  buffer : CodeBuffer,
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  block : @vcode.Block,
  successor_index : Int,
) -> Unit raise X64EmitError {
  emit_resolved_moves(
    buffer,
    frame,
    resolve_edge_moves(function, allocation, block, successor_index),
  )
}

///|
/// Chase a branch target through empty forwarding blocks.
///
/// Lowering splits critical edges, so a branch frequently targets a block
/// whose only content is an unconditional jump carrying the edge arguments.
/// When allocation gives those arguments and the destination parameters the
/// same locations, the block emits as a single `jmp`, and a loop back edge
/// then pays two taken branches per iteration instead of one. Branching
/// straight to the final destination removes the hop.
///
/// A block is skipped only when nothing observable happens in it: no body
/// instructions, no allocation edits anchored on its terminator, and an edge
/// whose parallel moves resolve to nothing. The forwarding block itself is
/// still emitted, so predecessors that do need its moves keep their path.
fn threaded_branch_target(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  target : @vcode.Block,
) -> @vcode.Block raise X64EmitError {
  let mut current = target
  // Forwarding chains longer than a few hops do not occur in practice; the
  // bound also terminates on a cycle of empty blocks.
  for _hop in 0..<4 {
    if !function.block_body(current).is_empty() {
      break
    }
    guard function.block_terminator(current) is Some(terminator) else { break }
    guard function.instruction(terminator) is Some(Jump) else { break }
    if !allocation.edits_at(terminator, Before).is_empty() ||
      !allocation.edits_at(terminator, After).is_empty() {
      break
    }
    if !resolve_edge_moves(function, allocation, current, 0).steps.is_empty() {
      break
    }
    guard function.instruction_successor_at(terminator, 0) is Some(edge) else {
      break
    }
    if edge.target == current {
      break
    }
    current = edge.target
  }
  current
}

///|
fn emit_conditional_edges(
  buffer : CodeBuffer,
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
  condition : @vcode.PhysicalReg,
  next_block : @vcode.Block?,
) -> Unit raise X64EmitError {
  let when_true = function.instruction_successor_at(instruction, 0).unwrap().target
  let when_false = function.instruction_successor_at(instruction, 1).unwrap().target
  let true_moves = resolve_edge_moves(function, allocation, block, 0)
  let false_moves = resolve_edge_moves(function, allocation, block, 1)
  // Fallthrough decisions compare the original successors; emitted branches
  // go to the threaded targets. The edge's own moves are emitted here either
  // way, so threading only skips blocks that contribute nothing.
  let threaded_true = function
    .block_index(threaded_branch_target(function, allocation, when_true))
    .unwrap()
  let threaded_false = function
    .block_index(threaded_branch_target(function, allocation, when_false))
    .unwrap()
  buffer.x86_emit_test_rr32(condition.id, condition.id)
  if next_block == Some(when_false) {
    if true_moves.steps.is_empty() {
      buffer.x86_emit_jcc_rel32(RawNe, threaded_true)
      emit_resolved_moves(buffer, frame, false_moves)
    } else {
      buffer.emit_byte(0x0F)
      buffer.emit_byte(x86_cond_to_jcc_opcode(RawEq))
      let local_false_branch = buffer.position()
      emit_u32_le(buffer, 0)
      emit_resolved_moves(buffer, frame, true_moves)
      buffer.x86_emit_jmp_rel32(threaded_true)
      patch_relative_branch(buffer, local_false_branch, buffer.position(), 32)
      emit_resolved_moves(buffer, frame, false_moves)
    }
  } else if next_block == Some(when_true) {
    if false_moves.steps.is_empty() {
      buffer.x86_emit_jcc_rel32(RawEq, threaded_false)
      emit_resolved_moves(buffer, frame, true_moves)
    } else {
      buffer.emit_byte(0x0F)
      buffer.emit_byte(x86_cond_to_jcc_opcode(RawNe))
      let local_true_branch = buffer.position()
      emit_u32_le(buffer, 0)
      emit_resolved_moves(buffer, frame, false_moves)
      buffer.x86_emit_jmp_rel32(threaded_false)
      patch_relative_branch(buffer, local_true_branch, buffer.position(), 32)
      emit_resolved_moves(buffer, frame, true_moves)
    }
  } else if true_moves.steps.is_empty() {
    buffer.x86_emit_jcc_rel32(RawNe, threaded_true)
    emit_resolved_moves(buffer, frame, false_moves)
    buffer.x86_emit_jmp_rel32(threaded_false)
  } else if false_moves.steps.is_empty() {
    buffer.x86_emit_jcc_rel32(RawEq, threaded_false)
    emit_resolved_moves(buffer, frame, true_moves)
    buffer.x86_emit_jmp_rel32(threaded_true)
  } else {
    buffer.emit_byte(0x0F)
    buffer.emit_byte(x86_cond_to_jcc_opcode(RawEq))
    let local_false_branch = buffer.position()
    emit_u32_le(buffer, 0)
    emit_resolved_moves(buffer, frame, true_moves)
    buffer.x86_emit_jmp_rel32(threaded_true)
    patch_relative_branch(buffer, local_false_branch, buffer.position(), 32)
    emit_resolved_moves(buffer, frame, false_moves)
    buffer.x86_emit_jmp_rel32(threaded_false)
  }
}

///|
fn emit_switch_compare(
  buffer : CodeBuffer,
  width : GprWidth,
  index : @vcode.PhysicalReg,
  bits : UInt64,
) -> Unit {
  if bits <= 0x7FFFFFFFUL {
    if width == W32 {
      buffer.x86_emit_cmp_r32_imm32(index.id, bits.to_int())
    } else {
      buffer.x86_emit_cmp_r_imm32(index.id, bits.to_int())
    }
  } else {
    let scratch = @vcode.PhysicalReg::new(11, Int)
    emit_constant(buffer, width, scratch, bits)
    if width == W32 {
      buffer.x86_emit_cmp_rr32(index.id, scratch.id)
    } else {
      buffer.x86_emit_cmp_rr(index.id, scratch.id)
    }
  }
}

///|
fn emit_switch_edges(
  buffer : CodeBuffer,
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
  width : GprWidth,
  cases : Array[UInt64],
  index : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  if cases.is_empty() {
    emit_edge_moves(buffer, function, allocation, frame, block, 0)
    buffer.x86_emit_jmp_rel32(
      function
      .block_index(
        threaded_branch_target(
          function,
          allocation,
          function.instruction_successor_at(instruction, 0).unwrap().target,
        ),
      )
      .unwrap(),
    )
    return
  }
  let case_branches : Array[(Int, Int)] = []
  for successor_index, bits in cases {
    emit_switch_compare(buffer, width, index, bits)
    buffer.emit_byte(0x0F)
    buffer.emit_byte(x86_cond_to_jcc_opcode(RawEq))
    case_branches.push((buffer.position(), successor_index))
    emit_u32_le(buffer, 0)
  }
  emit_edge_moves(buffer, function, allocation, frame, block, cases.length())
  buffer.x86_emit_jmp_rel32(
    function
    .block_index(
      threaded_branch_target(
        function,
        allocation,
        function.instruction_successor_at(instruction, cases.length()).unwrap().target,
      ),
    )
    .unwrap(),
  )
  for entry in case_branches {
    let (branch, successor_index) = entry
    patch_relative_branch(buffer, branch, buffer.position(), 32)
    emit_edge_moves(buffer, function, allocation, frame, block, successor_index)
    buffer.x86_emit_jmp_rel32(
      function
      .block_index(
        threaded_branch_target(
          function,
          allocation,
          function
          .instruction_successor_at(instruction, successor_index)
          .unwrap().target,
        ),
      )
      .unwrap(),
    )
  }
}
