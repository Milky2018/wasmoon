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
fn emit_resolved_moves(
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
  if next_block == Some(when_false) {
    if true_moves.is_empty() {
      buffer.emit_branch(when_true, 19, true_branch_base)
      emit_resolved_moves(buffer, frame, false_moves)
    } else {
      let local_false_branch = buffer.position()
      buffer.emit_word(false_branch_base)
      emit_resolved_moves(buffer, frame, true_moves)
      buffer.emit_branch(when_true, 26, 0x14000000U)
      patch_relative_branch(buffer, local_false_branch, buffer.position(), 19)
      emit_resolved_moves(buffer, frame, false_moves)
    }
  } else if next_block == Some(when_true) {
    if false_moves.is_empty() {
      buffer.emit_branch(when_false, 19, false_branch_base)
      emit_resolved_moves(buffer, frame, true_moves)
    } else {
      let local_true_branch = buffer.position()
      buffer.emit_word(true_branch_base)
      emit_resolved_moves(buffer, frame, false_moves)
      buffer.emit_branch(when_false, 26, 0x14000000U)
      patch_relative_branch(buffer, local_true_branch, buffer.position(), 19)
      emit_resolved_moves(buffer, frame, true_moves)
    }
  } else if true_moves.is_empty() {
    buffer.emit_branch(when_true, 19, true_branch_base)
    emit_resolved_moves(buffer, frame, false_moves)
    buffer.emit_branch(when_false, 26, 0x14000000U)
  } else {
    let local_true_branch = buffer.position()
    buffer.emit_word(true_branch_base)
    emit_resolved_moves(buffer, frame, false_moves)
    buffer.emit_branch(when_false, 26, 0x14000000U)
    patch_relative_branch(buffer, local_true_branch, buffer.position(), 19)
    emit_resolved_moves(buffer, frame, true_moves)
    buffer.emit_branch(when_true, 26, 0x14000000U)
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
      function.instruction_successor_at(instruction, 0).unwrap().target,
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
    let default_branch : Int? = if default_moves.is_empty() {
      buffer.emit_branch(
        function.instruction_successor_at(instruction, default_index).unwrap().target,
        19,
        0x54000002U,
      )
      None
    } else {
      let branch = buffer.position()
      buffer.emit_word(0x54000002U)
      Some(branch)
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
      if edge_parallel_moves(function, allocation, block, successor_index).is_empty() {
        buffer.emit_branch(
          function
          .instruction_successor_at(instruction, successor_index)
          .unwrap().target,
          26,
          0x14000000U,
        )
      } else {
        stubs.push((buffer.position(), successor_index))
        buffer.emit_word(0x14000000U)
      }
    }
    for stub in stubs {
      let (branch, successor_index) = stub
      patch_relative_branch(buffer, branch, buffer.position(), 26)
      emit_edge_moves(
        buffer, function, allocation, frame, block, successor_index,
      )
      buffer.emit_branch(
        function.instruction_successor_at(instruction, successor_index).unwrap().target,
        26,
        0x14000000U,
      )
    }
    if default_branch is Some(branch) {
      patch_relative_branch(buffer, branch, buffer.position(), 19)
      emit_resolved_moves(buffer, frame, default_moves)
      buffer.emit_branch(
        function.instruction_successor_at(instruction, default_index).unwrap().target,
        26,
        0x14000000U,
      )
    }
    return
  } else {
    let case_branches : Array[(Int, Int)] = []
    for successor_index, bits in cases {
      emit_switch_compare(buffer, width, index, bits)
      if edge_parallel_moves(function, allocation, block, successor_index).is_empty() {
        buffer.emit_branch(
          function
          .instruction_successor_at(instruction, successor_index)
          .unwrap().target,
          19,
          0x54000000U,
        )
      } else {
        case_branches.push((buffer.position(), successor_index))
        buffer.emit_word(0x54000000U)
      }
    }
    emit_edge_moves(buffer, function, allocation, frame, block, cases.length())
    buffer.emit_branch(
      function.instruction_successor_at(instruction, cases.length()).unwrap().target,
      26,
      0x14000000U,
    )
    for entry in case_branches {
      let (branch, successor_index) = entry
      patch_relative_branch(buffer, branch, buffer.position(), 19)
      emit_edge_moves(
        buffer, function, allocation, frame, block, successor_index,
      )
      buffer.emit_branch(
        function.instruction_successor_at(instruction, successor_index).unwrap().target,
        26,
        0x14000000U,
      )
    }
    return
  }
}
