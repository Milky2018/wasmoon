///|
fn resolve_edge_moves(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  block : @vcode.Block,
  successor_index : Int32,
) -> @vcode.ResolvedMovePlan raise AArch64EmitError {
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
  frame : AArch64Frame,
  plan : @vcode.ResolvedMovePlan,
) -> Unit raise AArch64EmitError {
  @vcode.emit_resolved_moves(
    plan,
    buffer,
    frame,
    AArch64Frame::slot_offset,
    AArch64Frame::emergency_move_offset,
    emit_move,
    emit_stack_access,
    UnresolvedStackMove,
    MissingEmergencyMoveArea,
  )
}

///|
fn threaded_branch_target(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  target : @vcode.Block,
) -> @vcode.Block raise AArch64EmitError {
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
fn emit_edge_moves(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  block : @vcode.Block,
  successor_index : Int32,
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
  true_branch_base : UInt32,
  false_branch_base : UInt32,
  next_block : @vcode.Block?,
) -> Unit raise AArch64EmitError {
  let layout = @vcode.plan_conditional_edges(
    function,
    allocation,
    block,
    instruction,
    next_block,
    Jump,
    int_transfer_scratch(),
    fp_transfer_scratch(),
    split_false_first=true,
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
  let first_branch = if layout.first_when_true {
    true_branch_base
  } else {
    false_branch_base
  }
  if layout.direct_branch {
    buffer.emit_branch(layout.first_target, 19, first_branch)
  } else {
    // The span over the first edge's moves is data-dependent and can widen.
    let second_branch = if layout.first_when_true {
      false_branch_base
    } else {
      true_branch_base
    }
    let past_moves = buffer.new_label()
    buffer.emit_label_branch(past_moves, 19, second_branch)
    emit_resolved_moves(buffer, frame, layout.first_moves)
    buffer.emit_branch(layout.first_target, 26, 0x14000000U)
    buffer.bind_label(past_moves)
  }
  emit_resolved_moves(buffer, frame, layout.second_moves)
  if !layout.second_falls_through {
    buffer.emit_branch(layout.second_target, 26, 0x14000000U)
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
  // Directly index a permutation of 0..<case_count. Sparse keys and
  // duplicates use comparisons, even when emission is called directly.
  let case_count = cases.length()
  let dense_order = if cases.iter().all(bits => bits < case_count.to_uint64()) {
    let order = Array::make(case_count, -1)
    for successor_index, bits in cases {
      let key = bits.to_int()
      if order[key] != -1 {
        break None
      }
      order[key] = successor_index
    } nobreak {
      Some(order)
    }
  } else {
    None
  }
  if dense_order is Some(dense_order) {
    emit_switch_compare(buffer, width, index, cases.length().to_uint64())
    let default_index = cases.length()
    let default_moves = resolve_edge_moves(
      function, allocation, block, default_index,
    )
    let default_branch : Int32? = if default_moves.steps.is_empty() {
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
    let stubs : Array[(Int32, Int32)] = []
    for successor_index in dense_order {
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
    let case_branches : Array[(Int32, Int32)] = []
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
