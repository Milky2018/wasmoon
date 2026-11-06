///|
priv struct TailCallFramePlan {
  stack_argument_size : Int32
  stack_argument_base : Int32
  synthetic_return_size : Int32
  alignment_padding : Int32
  transfer_size : Int32
  thunk_cleanup_size : Int32
}

///|
pub struct X64Frame {
  priv layout : @vcode.FrameLayout
  priv has_setup_area : Bool
  priv storage : @vcode.FrameStorage
  priv incoming_args_size : Int32
  priv tail_args_size : Int32
  priv outgoing_args_size : Int32
  priv allocation_edit_count : Int32
}

///|
#derive(Debug)
pub suberror X64FrameError {
  InvalidAllocation(cause~ : X64AllocationError)
  InvalidGenericFrame(cause~ : @vcode.FrameVerifyError)
  InvalidSavedRegister(reg~ : @vcode.PhysicalReg, offset~ : Int32)
  InvalidStackSlot(slot~ : @vcode.StackSlot)
  OutgoingAreaMismatch(expected~ : Int32, actual~ : Int32)
  ResultAreaMismatch(expected~ : Int32, actual~ : Int32)
  TailAreaMismatch(
    expected_incoming~ : Int32,
    actual_incoming~ : Int32,
    expected_tail~ : Int32,
    actual_tail~ : Int32
  )
  InvalidStackObjectArea(message~ : String)
  MovePlanningFailed(cause~ : @vcode.MoveResolveError)
  CallPlanningFailed(cause~ : @vcode.CallTransferError)
  InvalidEmergencyMoveArea(offset~ : Int32?)
  StaleAllocation(expected_edits~ : Int32, actual_edits~ : Int32)
  SavedRegisterSetMismatch
}

///|
pub impl Show for X64FrameError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn is_callee_saved(reg : @vcode.PhysicalReg) -> Bool {
  match reg.class {
    Int => reg.id == 3 || (reg.id >= 12 && reg.id <= 15)
    Float | Vector | FpVector => false
  }
}

///|
fn frame_requirements(
  function : @vcode.Function[X64Inst],
) -> @vcode.FrameRequirements raise X64FrameError {
  match
    @vcode.collect_frame_requirements(function, inst => {
      match inst {
        PlatformCall(_, signature) | ReturnsTwicePlatformCall(_, signature) =>
          Some(Call(platform_call_layout(signature.params).stack_size, 0))
        InternalCall(_, _, plan) | InternalCallIndirect(_, plan) =>
          Some(Call(plan.stack_size, plan.result_area_size))
        TailCallDirect(_, _, plan) | TailCallIndirect(_, plan) =>
          Some(Tail(plan.stack_size))
        IncomingStack(ty, offset) =>
          Some(Incoming(offset + @vcode.call_stack_size(ty)))
        StackAddress(object) =>
          Some(LocalObject(object.id, object.size, object.alignment))
        _ => None
      }
    }) {
    Ok(requirements) => requirements
    Err(message) => raise InvalidStackObjectArea(message~)
  }
}

///|
pub fn X64Frame::frame_size(self : X64Frame) -> Int32 {
  if self.has_setup_area {
    self.layout.frame_size() + 8
  } else {
    self.layout.frame_size()
  }
}

///|
fn X64Frame::allocation_size(self : X64Frame) -> Int32 {
  self.layout.frame_size()
}

///|
fn X64Frame::has_setup_area(self : X64Frame) -> Bool {
  self.has_setup_area
}

///|
pub fn X64Frame::incoming_args_size(self : X64Frame) -> Int32 {
  self.incoming_args_size
}

///|
pub fn X64Frame::tail_args_size(self : X64Frame) -> Int32 {
  self.tail_args_size
}

///|
fn X64Frame::tail_call_plan(
  self : X64Frame,
  callee_args_size : Int32,
) -> TailCallFramePlan {
  if callee_args_size <= self.incoming_args_size {
    {
      stack_argument_size: callee_args_size,
      stack_argument_base: self.frame_size() + 8,
      synthetic_return_size: 0,
      alignment_padding: 0,
      transfer_size: 0,
      thunk_cleanup_size: 0,
    }
  } else {
    let synthetic_return_size = 8
    let transfer_size = align_up(synthetic_return_size + callee_args_size, 16)
    let alignment_padding = transfer_size -
      synthetic_return_size -
      callee_args_size
    {
      stack_argument_size: callee_args_size,
      stack_argument_base: self.frame_size() +
      synthetic_return_size -
      transfer_size,
      synthetic_return_size,
      alignment_padding,
      transfer_size,
      thunk_cleanup_size: transfer_size - synthetic_return_size,
    }
  }
}

///|
fn X64Frame::valid_tail_call_plan(
  self : X64Frame,
  plan : TailCallFramePlan,
) -> Bool {
  if plan.stack_argument_size <= self.incoming_args_size {
    return plan.stack_argument_base == self.frame_size() + 8 &&
      plan.synthetic_return_size == 0 &&
      plan.alignment_padding == 0 &&
      plan.transfer_size == 0 &&
      plan.thunk_cleanup_size == 0
  }
  plan.stack_argument_size % 16 == 0 &&
  plan.synthetic_return_size == 8 &&
  plan.alignment_padding >= 0 &&
  plan.synthetic_return_size + plan.stack_argument_size + plan.alignment_padding ==
  plan.transfer_size &&
  plan.transfer_size % 16 == 0 &&
  plan.stack_argument_base ==
  self.frame_size() + plan.synthetic_return_size - plan.transfer_size &&
  plan.thunk_cleanup_size + plan.synthetic_return_size == plan.transfer_size
}

///|
fn tail_argument_staging_size(
  incoming_args_size : Int32,
  tail_args_size : Int32,
) -> Int32 {
  if tail_args_size > incoming_args_size {
    tail_args_size
  } else {
    0
  }
}

///|
pub fn X64Frame::alignment(self : X64Frame) -> Int32 {
  self.layout.alignment()
}

///|
pub fn X64Frame::outgoing_args_size(self : X64Frame) -> Int32 {
  self.outgoing_args_size
}

///|
fn X64Frame::result_area_offset(self : X64Frame) -> Int32? {
  self.storage.result_area_offset()
}

///|
pub fn X64Frame::emergency_move_offset(self : X64Frame) -> Int32? {
  self.storage.emergency_move_offset()
}

///|
pub fn X64Frame::stack_object_offset(
  self : X64Frame,
  object : X64StackObject,
) -> Int32? {
  if object.is_valid() {
    self.storage.stack_object_offset(object.id)
  } else {
    None
  }
}

///|
pub fn X64Frame::slot_offset(
  self : X64Frame,
  slot : @vcode.StackSlot,
) -> Int32? {
  self.layout.slot_offset(slot)
}

///|
pub fn X64Frame::saved_registers(
  self : X64Frame,
) -> Array[(@vcode.PhysicalReg, Int32)] {
  self.storage.saved_registers()
}

///|
pub fn X64Frame::summary(self : X64Frame) -> String {
  let mut output = "x64 frame size=\{self.frame_size()} align=\{self.alignment()}\n"
  if self.tail_args_size > self.incoming_args_size {
    let plan = self.tail_call_plan(self.tail_args_size)
    output += "  tail-args \{plan.stack_argument_size} bytes at sp+\{plan.stack_argument_base}\n"
    output += "  tail-transfer return=\{plan.synthetic_return_size} padding=\{plan.alignment_padding} adjust=\{plan.transfer_size} cleanup=\{plan.thunk_cleanup_size}\n"
  }
  output + self.storage.summary(self.outgoing_args_size)
}

///|
pub fn verify_frame(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
) -> Unit raise X64FrameError {
  verify_allocation(function, allocation) catch {
    error => raise InvalidAllocation(cause=error)
  }
  @vcode.verify_framed(function, allocation, frame.layout) catch {
    error => raise InvalidGenericFrame(cause=error)
  }
  verify_target_frame(function, allocation, frame)
}

///|
fn verify_target_frame(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
) -> Unit raise X64FrameError {
  let actual_edit_count = allocation.edit_count()
  if frame.allocation_edit_count != actual_edit_count {
    raise StaleAllocation(
      expected_edits=frame.allocation_edit_count,
      actual_edits=actual_edit_count,
    )
  }
  let requirements = frame_requirements(function)
  let expected_outgoing = requirements.outgoing_args_size
  if frame.outgoing_args_size != expected_outgoing {
    raise OutgoingAreaMismatch(
      expected=expected_outgoing,
      actual=frame.outgoing_args_size,
    )
  }
  let expected_incoming = requirements.incoming_args_size
  let expected_tail = requirements.tail_args_size
  let expected_tail_area = tail_argument_staging_size(
    expected_incoming, expected_tail,
  )
  if frame.incoming_args_size != expected_incoming ||
    frame.tail_args_size != expected_tail ||
    frame.storage.local_size() + expected_tail_area != frame.allocation_size() {
    raise TailAreaMismatch(
      expected_incoming~,
      actual_incoming=frame.incoming_args_size,
      expected_tail~,
      actual_tail=frame.tail_args_size,
    )
  }
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    let stack_arguments = match function.instruction(instruction) {
      Some(TailCallDirect(_, _, plan) | TailCallIndirect(_, plan)) =>
        Some(plan.stack_size)
      _ => None
    }
    if stack_arguments is Some(size) &&
      !frame.valid_tail_call_plan(frame.tail_call_plan(size)) {
      raise TailAreaMismatch(
        expected_incoming~,
        actual_incoming=frame.incoming_args_size,
        expected_tail=size,
        actual_tail=frame.tail_args_size,
      )
    }
  }
  let expected = frame_saved_registers(function, allocation)
  frame.storage.verify(frame.layout, allocation, requirements, expected) catch {
    InvalidSavedRegister(reg~, offset~) =>
      raise InvalidSavedRegister(reg~, offset~)
    InvalidStackSlot(slot~) => raise InvalidStackSlot(slot~)
    ResultAreaMismatch(expected~, actual~) =>
      raise ResultAreaMismatch(expected~, actual~)
    InvalidStackObjectArea(message~) => raise InvalidStackObjectArea(message~)
    InvalidEmergencyMoveArea(offset~) => raise InvalidEmergencyMoveArea(offset~)
    SavedRegisterSetMismatch => raise SavedRegisterSetMismatch
  }
}

///|
fn plan_frame_verified(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
) -> X64Frame raise X64FrameError {
  let requirements = frame_requirements(function)
  let outgoing_args_size = requirements.outgoing_args_size
  let requires_emergency_moves = @vcode.requires_emergency_move_area(
    function,
    allocation,
    is_abi_materialization,
    int_transfer_scratch(),
    fp_transfer_scratch(),
  ) catch {
    error => raise MovePlanningFailed(cause=error)
  }
  let storage = @vcode.FrameStorage::plan(
    requirements,
    allocation,
    requires_emergency_moves,
    frame_saved_registers(function, allocation),
  )
  let local_size = storage.local_size()
  let incoming_args_size = requirements.incoming_args_size
  let tail_args_size = requirements.tail_args_size
  let tail_area_size = tail_argument_staging_size(
    incoming_args_size, tail_args_size,
  )
  let allocation_size = local_size + tail_area_size
  let layout = @vcode.FrameLayout::new(
    function, allocation, allocation_size, 16,
  )
  storage.place_slots(layout)
  let frame = {
    layout,
    has_setup_area: function.protocol() == Internal ||
    allocation_size > 0 ||
    requirements.has_calls,
    storage,
    incoming_args_size,
    tail_args_size,
    outgoing_args_size,
    allocation_edit_count: allocation.edit_count(),
  }
  verify_target_frame(function, allocation, frame)
  frame
}

///|
pub fn plan_frame(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
) -> X64Frame raise X64FrameError {
  verify_allocation(function, allocation) catch {
    error => raise InvalidAllocation(cause=error)
  }
  plan_frame_verified(function, allocation)
}
