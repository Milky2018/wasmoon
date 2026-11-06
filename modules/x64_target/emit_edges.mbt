///|
fn resolve_edge_moves(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  block : @vcode.Block,
  successor_index : Int32,
) -> @vcode.ResolvedMovePlan raise X64EmitError {
  @vcode.resolve_edge_moves(
    function,
    allocation,
    block,
    successor_index,
    int_transfer_scratch(),
    fp_transfer_scratch(),
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
}

///|
fn emit_resolved_moves(
  buffer : CodeBuffer,
  frame : X64Frame,
  plan : @vcode.ResolvedMovePlan,
) -> Unit raise X64EmitError {
  @vcode.emit_resolved_moves(
    plan,
    buffer,
    frame,
    X64Frame::slot_offset,
    X64Frame::emergency_move_offset,
    emit_move,
    emit_stack_access,
    UnresolvedStackMove,
    MissingEmergencyMoveArea,
  )
}

///|
fn emit_edge_moves(
  buffer : CodeBuffer,
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  block : @vcode.Block,
  successor_index : Int32,
) -> Unit raise X64EmitError {
  emit_resolved_moves(
    buffer,
    frame,
    resolve_edge_moves(function, allocation, block, successor_index),
  )
}

///|
fn threaded_branch_target(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  target : @vcode.Block,
) -> @vcode.Block raise X64EmitError {
  @vcode.threaded_branch_target(
    function,
    allocation,
    target,
    Jump,
    int_transfer_scratch(),
    fp_transfer_scratch(),
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
}

///|
// The caller emits CMP/TEST. Test its flags before edge moves can clobber them.
fn emit_conditional_edges(
  buffer : CodeBuffer,
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
  condition : X64Condition,
  next_block : @vcode.Block?,
) -> Unit raise X64EmitError {
  let layout = @vcode.plan_conditional_edges(
    function,
    allocation,
    block,
    instruction,
    next_block,
    Jump,
    int_transfer_scratch(),
    fp_transfer_scratch(),
    split_false_first=false,
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
  let first_target = function.block_index(layout.first_target).unwrap()
  let second_target = function.block_index(layout.second_target).unwrap()
  let inverse = inverse_condition(condition)
  let first_condition = if layout.first_when_true { condition } else { inverse }
  if layout.direct_branch {
    buffer.x86_emit_jcc_rel32(raw_condition(first_condition), first_target)
  } else {
    let second_condition = if layout.first_when_true {
      inverse
    } else {
      condition
    }
    buffer.emit_byte(0x0F)
    buffer.emit_byte(x86_cond_to_jcc_opcode(raw_condition(second_condition)))
    let past_moves = buffer.position()
    emit_u32_le(buffer.encoder, 0)
    emit_resolved_moves(buffer, frame, layout.first_moves)
    buffer.x86_emit_jmp_rel32(first_target)
    patch_relative_branch(buffer, past_moves, buffer.position(), 32)
  }
  emit_resolved_moves(buffer, frame, layout.second_moves)
  if !layout.second_falls_through {
    buffer.x86_emit_jmp_rel32(second_target)
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
      buffer.encoder.x86_emit_cmp_r32_imm32(index.id, bits.to_int())
    } else {
      buffer.encoder.x86_emit_cmp_r_imm32(index.id, bits.to_int())
    }
  } else {
    let scratch = @vcode.PhysicalReg::new(11, Int)
    emit_constant(buffer, width, scratch, bits)
    if width == W32 {
      buffer.encoder.x86_emit_gpr(Cmp, R32, index.id, scratch.id)
    } else {
      buffer.encoder.x86_emit_gpr(Cmp, R64, index.id, scratch.id)
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
  let case_branches : Array[(Int32, Int32)] = []
  for successor_index, bits in cases {
    emit_switch_compare(buffer, width, index, bits)
    buffer.emit_byte(0x0F)
    buffer.emit_byte(x86_cond_to_jcc_opcode(RawEq))
    case_branches.push((buffer.position(), successor_index))
    emit_u32_le(buffer.encoder, 0)
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
