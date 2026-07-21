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
) -> Array[@vcode.ParallelMove] raise X64EmitError {
  @vcode.resolve_parallel_moves(
    edge_parallel_moves(function, allocation, block, successor_index),
    [@vcode.PhysicalReg::new(10, Int), @vcode.PhysicalReg::new(11, Int)],
    [
      @vcode.PhysicalReg::new(14, FpVector),
      @vcode.PhysicalReg::new(15, FpVector),
    ],
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
  transfers : Array[@vcode.ParallelMove],
) -> Unit raise X64EmitError {
  for transfer in transfers {
    emit_location_move(buffer, frame, transfer)
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
  buffer.x86_emit_test_rr32(condition.id, condition.id)
  if next_block == Some(when_false) {
    if true_moves.is_empty() {
      buffer.x86_emit_jcc_rel32(RawNe, function.block_index(when_true).unwrap())
      emit_resolved_moves(buffer, frame, false_moves)
    } else {
      buffer.emit_byte(0x0F)
      buffer.emit_byte(x86_cond_to_jcc_opcode(RawEq))
      let local_false_branch = buffer.position()
      emit_u32_le(buffer, 0)
      emit_resolved_moves(buffer, frame, true_moves)
      buffer.x86_emit_jmp_rel32(function.block_index(when_true).unwrap())
      patch_relative_branch(buffer, local_false_branch, buffer.position(), 32)
      emit_resolved_moves(buffer, frame, false_moves)
    }
  } else if next_block == Some(when_true) {
    if false_moves.is_empty() {
      buffer.x86_emit_jcc_rel32(
        RawEq,
        function.block_index(when_false).unwrap(),
      )
      emit_resolved_moves(buffer, frame, true_moves)
    } else {
      buffer.emit_byte(0x0F)
      buffer.emit_byte(x86_cond_to_jcc_opcode(RawNe))
      let local_true_branch = buffer.position()
      emit_u32_le(buffer, 0)
      emit_resolved_moves(buffer, frame, false_moves)
      buffer.x86_emit_jmp_rel32(function.block_index(when_false).unwrap())
      patch_relative_branch(buffer, local_true_branch, buffer.position(), 32)
      emit_resolved_moves(buffer, frame, true_moves)
    }
  } else if true_moves.is_empty() {
    buffer.x86_emit_jcc_rel32(RawNe, function.block_index(when_true).unwrap())
    emit_resolved_moves(buffer, frame, false_moves)
    buffer.x86_emit_jmp_rel32(function.block_index(when_false).unwrap())
  } else if false_moves.is_empty() {
    buffer.x86_emit_jcc_rel32(RawEq, function.block_index(when_false).unwrap())
    emit_resolved_moves(buffer, frame, true_moves)
    buffer.x86_emit_jmp_rel32(function.block_index(when_true).unwrap())
  } else {
    buffer.emit_byte(0x0F)
    buffer.emit_byte(x86_cond_to_jcc_opcode(RawEq))
    let local_false_branch = buffer.position()
    emit_u32_le(buffer, 0)
    emit_resolved_moves(buffer, frame, true_moves)
    buffer.x86_emit_jmp_rel32(function.block_index(when_true).unwrap())
    patch_relative_branch(buffer, local_false_branch, buffer.position(), 32)
    emit_resolved_moves(buffer, frame, false_moves)
    buffer.x86_emit_jmp_rel32(function.block_index(when_false).unwrap())
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
        function.instruction_successor_at(instruction, 0).unwrap().target,
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
      function.instruction_successor_at(instruction, cases.length()).unwrap().target,
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
        function.instruction_successor_at(instruction, successor_index).unwrap().target,
      )
      .unwrap(),
    )
  }
}
