///|
/// R15 is reserved from allocation but late physical transfers may write it.
/// Include those writes in the platform-preserved set using the same transfer
/// plans as emission, without adding saves to functions that never use it.
fn frame_saved_registers(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
) -> Array[@vcode.PhysicalReg] raise X64FrameError {
  let saved = @vcode.used_callee_saved_registers(
    function, allocation, is_callee_saved,
  )
  let scratch = int_transfer_scratch()
  if !saved.contains(scratch) && transfer_uses_int_scratch(function, allocation) {
    saved.push(scratch)
  }
  saved
}

///|
fn transfer_uses_int_scratch(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
) -> Bool raise X64FrameError {
  let scratch = int_transfer_scratch()
  fn uses(plan : @vcode.ResolvedMovePlan) -> Bool {
    plan.steps.any(step => {
      match step {
        Transfer(transfer) => transfer.to == Register(scratch)
        SpillScratchToEmergency(scratch=reg, ..)
        | ReloadScratchFromEmergency(scratch=reg, ..) => reg == scratch
      }
    })
  }
  fn moves_use(moves : Array[@vcode.ParallelMove]) -> Bool raise X64FrameError {
    !moves.is_empty() &&
    uses(
      @vcode.plan_parallel_moves(moves, scratch, fp_transfer_scratch()) catch {
        error => raise MovePlanningFailed(cause=error)
      },
    )
  }
  for block in function.layout() {
    let moves : Array[@vcode.ParallelMove] = []
    let mut group = 0
    let body = function.block_body(block)
    for index in 0..<(body.length() + 1) {
      let instruction = if index < body.length() {
        body[index]
      } else {
        function.block_terminator(block).unwrap()
      }
      let inst = function.instruction(instruction).unwrap()
      let next_group = if is_function_input(inst) {
        1
      } else if is_function_output(inst) {
        2
      } else if is_incoming_call_result(inst) {
        3
      } else {
        0
      }
      if next_group != group {
        if moves_use(moves) {
          return true
        }
        moves.clear()
        group = next_group
      }
      let transfer = match inst {
        IncomingReg(ty, source) =>
          Some(
            @vcode.ParallelMove::new(
              ty,
              Register(source),
              value_home(function, allocation, instruction, 1),
            ),
          )
        IncomingResultArea(source) =>
          Some(
            @vcode.ParallelMove::new(
              Ptr64,
              Register(source),
              value_home(function, allocation, instruction, 0),
            ),
          )
        IncomingCallResult(ty, source) =>
          Some(
            @vcode.ParallelMove::new(
              ty,
              Register(source),
              value_home(function, allocation, instruction, 0),
            ),
          )
        OutgoingReg(ty, destination) =>
          Some(
            @vcode.ParallelMove::new(
              ty,
              value_home(function, allocation, instruction, 0),
              Register(destination),
            ),
          )
        _ => None
      }
      if transfer is Some(transfer) {
        moves.push(transfer)
      }
      if inst is IncomingCallAreaResult(ty, _) &&
        @vcode.reg_class_for_value_type(ty) == Int &&
        value_home(function, allocation, instruction, 0) is Stack(_) {
        return true
      }
      if group == 0 {
        for placement in [@vcode.PointPlacement::Before, After] {
          if !allocation.edits_at(instruction, placement).is_empty() &&
            moves_use(
              @vcode.allocation_edit_moves(
                function, allocation, instruction, placement,
              ),
            ) {
            return true
          }
        }
      }
      let call = instruction_call_plan(inst, allocation, instruction) catch {
        error => raise CallPlanningFailed(cause=error)
      }
      if call is Some(call) && uses(call.register_moves) {
        return true
      }
    }
    if moves_use(moves) {
      return true
    }
    let terminator = function.block_terminator(block).unwrap()
    for successor in 0..<function.instruction_successor_count(terminator) {
      let plan = @vcode.resolve_edge_moves(
        function,
        allocation,
        block,
        successor,
        scratch,
        fp_transfer_scratch(),
      ) catch {
        error => raise MovePlanningFailed(cause=error)
      }
      if uses(plan) {
        return true
      }
    }
  }
  false
}
