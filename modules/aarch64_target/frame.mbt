///|
pub struct AArch64Frame {
  priv layout : @vcode.FrameLayout
  priv has_frame_record : Bool
  priv storage : @vcode.FrameStorage
  priv incoming_args_size : Int32
  priv tail_args_size : Int32
  priv outgoing_args_size : Int32
  priv allocation_edit_count : Int32
}

///|
#derive(Debug)
pub suberror AArch64FrameError {
  InvalidAllocation(cause~ : AArch64AllocationError)
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
  InvalidEmergencyMoveArea(offset~ : Int32?)
  StaleAllocation(expected_edits~ : Int32, actual_edits~ : Int32)
  SavedRegisterSetMismatch
}

///|
pub impl Show for AArch64FrameError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn is_callee_saved(reg : @vcode.PhysicalReg) -> Bool {
  match reg.class {
    Int => reg.id >= 19 && reg.id <= 28
    Float | Vector | FpVector => reg.id >= 8 && reg.id <= 15
  }
}

///|
fn frame_requirements(
  function : @vcode.Function[AArch64Inst],
) -> @vcode.FrameRequirements raise AArch64FrameError {
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
fn used_callee_saved_registers(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  has_calls : Bool,
) -> Array[@vcode.PhysicalReg] {
  @vcode.used_callee_saved_registers(
    function,
    allocation,
    is_callee_saved,
    link_register=if function.protocol() != Internal && has_calls {
      Some(@vcode.PhysicalReg::new(30, Int))
    } else {
      None
    },
  )
}

///|
pub fn AArch64Frame::frame_size(self : AArch64Frame) -> Int32 {
  self.layout.frame_size() + (if self.has_frame_record { 16 } else { 0 })
}

///|
fn AArch64Frame::allocation_size(self : AArch64Frame) -> Int32 {
  self.layout.frame_size()
}

///|
pub fn AArch64Frame::incoming_args_size(self : AArch64Frame) -> Int32 {
  self.incoming_args_size
}

///|
pub fn AArch64Frame::tail_args_size(self : AArch64Frame) -> Int32 {
  self.tail_args_size
}

///|
fn AArch64Frame::tail_call_stack_base(
  self : AArch64Frame,
  callee_args_size : Int32,
) -> Int32 {
  if callee_args_size <= self.incoming_args_size {
    self.frame_size()
  } else {
    self.frame_size() - callee_args_size - 16
  }
}

///|
fn tail_cleanup_area_size(
  incoming_args_size : Int32,
  tail_args_size : Int32,
) -> Int32 {
  if tail_args_size > incoming_args_size {
    tail_args_size + 16
  } else {
    0
  }
}

///|
pub fn AArch64Frame::alignment(self : AArch64Frame) -> Int32 {
  self.layout.alignment()
}

///|
pub fn AArch64Frame::outgoing_args_size(self : AArch64Frame) -> Int32 {
  self.outgoing_args_size
}

///|
fn AArch64Frame::result_area_offset(self : AArch64Frame) -> Int32? {
  self.storage.result_area_offset()
}

///|
pub fn AArch64Frame::emergency_move_offset(self : AArch64Frame) -> Int32? {
  self.storage.emergency_move_offset()
}

///|
pub fn AArch64Frame::stack_object_offset(
  self : AArch64Frame,
  object : AArch64StackObject,
) -> Int32? {
  if object.is_valid() {
    self.storage.stack_object_offset(object.id)
  } else {
    None
  }
}

///|
pub fn AArch64Frame::slot_offset(
  self : AArch64Frame,
  slot : @vcode.StackSlot,
) -> Int32? {
  self.layout.slot_offset(slot)
}

///|
pub fn AArch64Frame::saved_registers(
  self : AArch64Frame,
) -> Array[(@vcode.PhysicalReg, Int32)] {
  self.storage.saved_registers()
}

///|
pub fn AArch64Frame::summary(self : AArch64Frame) -> String {
  let mut output = "aarch64 frame size=\{self.frame_size()} align=\{self.alignment()}\n"
  if self.tail_args_size > self.incoming_args_size {
    output += "  tail-args \{self.tail_args_size} bytes at sp+\{self.storage.local_size()} (incoming \{self.incoming_args_size})\n"
  }
  output + self.storage.summary(self.outgoing_args_size)
}

///|
pub fn verify_frame(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
) -> Unit raise AArch64FrameError {
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
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
) -> Unit raise AArch64FrameError {
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
  let expected_tail_area = tail_cleanup_area_size(
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
  let expected = used_callee_saved_registers(
    function,
    allocation,
    requirements.has_calls,
  )
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
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
) -> AArch64Frame raise AArch64FrameError {
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
    used_callee_saved_registers(function, allocation, requirements.has_calls),
  )
  let local_size = storage.local_size()
  let incoming_args_size = requirements.incoming_args_size
  let tail_args_size = requirements.tail_args_size
  let tail_area_size = tail_cleanup_area_size(
    incoming_args_size, tail_args_size,
  )
  let layout = @vcode.FrameLayout::new(
    function,
    allocation,
    local_size + tail_area_size,
    16,
  )
  storage.place_slots(layout)
  let frame = {
    layout,
    has_frame_record: function.protocol() == Internal,
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
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
) -> AArch64Frame raise AArch64FrameError {
  verify_allocation(function, allocation) catch {
    error => raise InvalidAllocation(cause=error)
  }
  plan_frame_verified(function, allocation)
}
