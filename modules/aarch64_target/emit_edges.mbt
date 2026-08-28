///|
fn edge_parallel_moves(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  block : @vcode.Block,
  successor_index : Int,
) -> Array[@vcode.ParallelMove] {
  let transfers : Array[@vcode.ParallelMove] = []
  for edit in allocation.edge_edits_at(block, successor_index) {
    match edit.kind() {
      EdgeMove(value~, from~, to~, ..) =>
        transfers.push(
          @vcode.ParallelMove::new(
            function.value_type(value).unwrap(),
            from,
            to,
          ),
        )
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
) -> @vcode.ResolvedMovePlan raise AArch64EmitError {
  if allocation.edge_edits_at(block, successor_index).is_empty() {
    return @vcode.ResolvedMovePlan::empty()
  }
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
fn emit_resolved_moves(
  buffer : CodeBuffer,
  frame : AArch64Frame,
  plan : @vcode.ResolvedMovePlan,
) -> Unit raise AArch64EmitError {
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
/// Chase a branch target through empty forwarding blocks.
///
/// Lowering splits critical edges, so a branch frequently targets a block
/// whose only content is an unconditional jump carrying the edge arguments.
/// When allocation gives those arguments and the destination parameters the
/// same locations, the block emits as a single `b`, and a loop back edge then
/// pays two taken branches per iteration instead of one. Branching straight
/// to the final destination removes the hop.
///
/// A block is skipped only when nothing observable happens in it: no body
/// instructions, no allocation edits anchored on its terminator, and an edge
/// whose parallel moves resolve to nothing. The forwarding block itself is
/// still emitted, so predecessors that do need its moves keep their path.
///
/// Threading can lengthen a conditional branch's displacement, and imm19
/// reaches only ±1MB with no intra-function veneer support. That exposure
/// predates threading — every moveless edge already aims imm19 branches at
/// arbitrary blocks — and an overflow raises a structured BranchOutOfRange
/// at patch time rather than emitting a wrong offset.
fn threaded_branch_target(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  target : @vcode.Block,
) -> @vcode.Block raise AArch64EmitError {
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
fn emit_edge_moves(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  block : @vcode.Block,
  successor_index : Int,
) -> Unit raise AArch64EmitError {
  emit_resolved_moves(
    buffer,
    frame,
    resolve_edge_moves(function, allocation, block, successor_index),
  )
}

///|
fn emit_two_way_edges(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
  true_branch_base : UInt,
  false_branch_base : UInt,
  next_block : @vcode.Block?,
) -> Unit raise AArch64EmitError {
  let when_true = function.instruction_successor_at(instruction, 0).unwrap().target
  let when_false = function.instruction_successor_at(instruction, 1).unwrap().target
  let true_moves = resolve_edge_moves(function, allocation, block, 0)
  let false_moves = resolve_edge_moves(function, allocation, block, 1)
  // Fallthrough decisions compare the original successors; emitted branches
  // go to the threaded targets. The edge's own moves are emitted here either
  // way, so threading only skips blocks that contribute nothing.
  let threaded_true = threaded_branch_target(function, allocation, when_true)
  let threaded_false = threaded_branch_target(function, allocation, when_false)
  if next_block == Some(when_false) {
    if true_moves.steps.is_empty() {
      buffer.emit_branch(threaded_true, 19, true_branch_base)
      emit_resolved_moves(buffer, frame, false_moves)
    } else {
      // Skips the true edge's moves. The span is the size of those moves, so
      // it is data-dependent and has to be able to widen.
      let past_true_moves = buffer.new_label()
      buffer.emit_label_branch(past_true_moves, 19, false_branch_base)
      emit_resolved_moves(buffer, frame, true_moves)
      buffer.emit_branch(threaded_true, 26, 0x14000000U)
      buffer.bind_label(past_true_moves)
      emit_resolved_moves(buffer, frame, false_moves)
    }
  } else if next_block == Some(when_true) {
    if false_moves.steps.is_empty() {
      buffer.emit_branch(threaded_false, 19, false_branch_base)
      emit_resolved_moves(buffer, frame, true_moves)
    } else {
      let past_false_moves = buffer.new_label()
      buffer.emit_label_branch(past_false_moves, 19, true_branch_base)
      emit_resolved_moves(buffer, frame, false_moves)
      buffer.emit_branch(threaded_false, 26, 0x14000000U)
      buffer.bind_label(past_false_moves)
      emit_resolved_moves(buffer, frame, true_moves)
    }
  } else if true_moves.steps.is_empty() {
    buffer.emit_branch(threaded_true, 19, true_branch_base)
    emit_resolved_moves(buffer, frame, false_moves)
    buffer.emit_branch(threaded_false, 26, 0x14000000U)
  } else {
    let past_false_moves = buffer.new_label()
    buffer.emit_label_branch(past_false_moves, 19, true_branch_base)
    emit_resolved_moves(buffer, frame, false_moves)
    buffer.emit_branch(threaded_false, 26, 0x14000000U)
    buffer.bind_label(past_false_moves)
    emit_resolved_moves(buffer, frame, true_moves)
    buffer.emit_branch(threaded_true, 26, 0x14000000U)
  }
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
  width : GprWidth,
  next_block : @vcode.Block?,
) -> Unit raise AArch64EmitError {
  let zero_base = if width == W32 { 0x34000000U } else { 0xB4000000U }
  let nonzero_base = if width == W32 { 0x35000000U } else { 0xB5000000U }
  emit_two_way_edges(
    buffer,
    function,
    allocation,
    frame,
    block,
    instruction,
    nonzero_base | reg_bits(condition),
    zero_base | reg_bits(condition),
    next_block,
  )
}

///|
fn emit_switch_compare(
  buffer : CodeBuffer,
  width : GprWidth,
  index : @vcode.PhysicalReg,
  bits : UInt64,
) -> Unit {
  let width_bit = if width == W32 { 0U } else { 0x80000000U }
  if bits <= 4095UL {
    buffer.emit_word(
      0x7100001FU | width_bit | (bits.to_uint() << 10) | (reg_bits(index) << 5),
    )
  } else {
    let scratch = @vcode.PhysicalReg::new(17, Int)
    emit_constant(buffer, width, scratch, bits)
    buffer.emit_word(
      0x6B00001FU |
      width_bit |
      (reg_bits(scratch) << 16) |
      (reg_bits(index) << 5),
    )
  }
}

///|
fn emit_switch_edges(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
  width : GprWidth,
  cases : Array[UInt64],
  index : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  if cases.is_empty() {
    emit_edge_moves(buffer, function, allocation, frame, block, 0)
    buffer.emit_branch(
      threaded_branch_target(
        function,
        allocation,
        function.instruction_successor_at(instruction, 0).unwrap().target,
      ),
      26,
      0x14000000U,
    )
    return
  }
  let mut dense_zero_based = true
  for expected in 0..<cases.length() {
    if !cases.contains(expected.to_uint64()) {
      dense_zero_based = false
      break
    }
  }
  if dense_zero_based {
    emit_switch_compare(buffer, width, index, cases.length().to_uint64())
    let default_index = cases.length()
    let default_moves = resolve_edge_moves(
      function, allocation, block, default_index,
    )
    let default_branch : Int? = if default_moves.steps.is_empty() {
      buffer.emit_branch(
        threaded_branch_target(
          function,
          allocation,
          function.instruction_successor_at(instruction, default_index).unwrap().target,
        ),
        19,
        0x54000002U,
      )
      None
    } else {
      // Reaches past the whole jump table and every stub below it, so on a
      // switch with many cases this is the branch that outgrows imm19.
      let past_table = buffer.new_label()
      buffer.emit_label_branch(past_table, 19, 0x54000002U)
      Some(past_table)
    }
    // The table begins three instructions after ADR. UXTW is required for an
    // I32 index so stale upper register bits cannot escape the bounds check.
    buffer.emit_word(0x10000070U)
    let add_base = if width == W32 { 0x8B204000U } else { 0x8B000000U }
    buffer.emit_word(
      add_base | (reg_bits(index) << 16) | (2U << 10) | (16U << 5) | 16U,
    )
    buffer.emit_word(0xD61F0200U)
    let stubs : Array[(Int, Int)] = []
    for key in 0..<cases.length() {
      let mut successor_index = 0
      for index, bits in cases {
        if bits == key.to_uint64() {
          successor_index = index
        }
      }
      if allocation.edge_edits_at(block, successor_index).is_empty() {
        buffer.emit_branch(
          threaded_branch_target(
            function,
            allocation,
            function
            .instruction_successor_at(instruction, successor_index)
            .unwrap().target,
          ),
          26,
          0x14000000U,
        )
      } else {
        // One word, like every other table entry: the `adr`/`add`/`br` above
        // indexes this table by instruction, so the stride cannot change.
        let stub = buffer.new_label()
        stubs.push((stub, successor_index))
        buffer.emit_label_branch(stub, 26, 0x14000000U)
      }
    }
    for entry in stubs {
      let (stub, successor_index) = entry
      buffer.bind_label(stub)
      emit_edge_moves(
        buffer, function, allocation, frame, block, successor_index,
      )
      buffer.emit_branch(
        threaded_branch_target(
          function,
          allocation,
          function
          .instruction_successor_at(instruction, successor_index)
          .unwrap().target,
        ),
        26,
        0x14000000U,
      )
    }
    if default_branch is Some(label) {
      buffer.bind_label(label)
      emit_resolved_moves(buffer, frame, default_moves)
      buffer.emit_branch(
        threaded_branch_target(
          function,
          allocation,
          function.instruction_successor_at(instruction, default_index).unwrap().target,
        ),
        26,
        0x14000000U,
      )
    }
    return
  } else {
    let case_branches : Array[(Int, Int)] = []
    for successor_index, bits in cases {
      emit_switch_compare(buffer, width, index, bits)
      if allocation.edge_edits_at(block, successor_index).is_empty() {
        buffer.emit_branch(
          threaded_branch_target(
            function,
            allocation,
            function
            .instruction_successor_at(instruction, successor_index)
            .unwrap().target,
          ),
          19,
          0x54000000U,
        )
      } else {
        // Each of these reaches past every stub emitted before its own, so the
        // last case in a large switch is the furthest reach in the function.
        let stub = buffer.new_label()
        case_branches.push((stub, successor_index))
        buffer.emit_label_branch(stub, 19, 0x54000000U)
      }
    }
    emit_edge_moves(buffer, function, allocation, frame, block, cases.length())
    buffer.emit_branch(
      threaded_branch_target(
        function,
        allocation,
        function.instruction_successor_at(instruction, cases.length()).unwrap().target,
      ),
      26,
      0x14000000U,
    )
    for entry in case_branches {
      let (stub, successor_index) = entry
      buffer.bind_label(stub)
      emit_edge_moves(
        buffer, function, allocation, frame, block, successor_index,
      )
      buffer.emit_branch(
        threaded_branch_target(
          function,
          allocation,
          function
          .instruction_successor_at(instruction, successor_index)
          .unwrap().target,
        ),
        26,
        0x14000000U,
      )
    }
    return
  }
}
