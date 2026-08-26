///|
priv struct SavedRegister {
  reg : @vcode.PhysicalReg
  offset : Int
}

///|
priv struct StackObjectArea {
  offset : Int
  size : Int
  alignment : Int
}

///|
priv struct ResultArea {
  offset : Int
  size : Int
}

///|
pub struct X64Frame {
  priv layout : @vcode.FrameLayout
  priv has_setup_area : Bool
  priv local_size : Int
  priv incoming_args_size : Int
  priv tail_args_size : Int
  priv outgoing_args_size : Int
  priv result_area : ResultArea?
  priv stack_objects : StackObjectArea?
  priv emergency_move_offset : Int?
  priv slots : Array[(@vcode.StackSlot, Int)]
  priv saved_registers : Array[SavedRegister]
}

///|
pub suberror X64FrameError {
  InvalidAllocation(cause~ : X64AllocationError)
  InvalidGenericFrame(cause~ : @vcode.FrameVerifyError)
  InvalidSavedRegister(reg~ : @vcode.PhysicalReg, offset~ : Int)
  InvalidStackSlot(slot~ : @vcode.StackSlot)
  OutgoingAreaMismatch(expected~ : Int, actual~ : Int)
  ResultAreaMismatch(expected~ : Int, actual~ : Int)
  TailAreaMismatch(
    expected_incoming~ : Int,
    actual_incoming~ : Int,
    expected_tail~ : Int,
    actual_tail~ : Int
  )
  InvalidStackObjectArea(message~ : String)
  MovePlanningFailed(cause~ : @vcode.MoveResolveError)
  InvalidEmergencyMoveArea(offset~ : Int?)
  SavedRegisterSetMismatch
} derive(Debug)

///|
pub impl Show for X64FrameError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn is_callee_saved(reg : @vcode.PhysicalReg) -> Bool {
  match reg.class {
    Int => reg.id == 3 || (reg.id >= 12 && reg.id <= 15)
    FpVector => false
  }
}

///|
fn register_save_size(reg : @vcode.PhysicalReg) -> Int {
  ignore(reg)
  8
}

///|
fn used_callee_saved_registers(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
) -> Array[@vcode.PhysicalReg] {
  let regs : Array[@vcode.PhysicalReg] = []
  fn record(
    regs : Array[@vcode.PhysicalReg],
    reg : @vcode.PhysicalReg,
  ) -> Unit {
    if is_callee_saved(reg) && !regs.contains(reg) {
      regs.push(reg)
    }
  }
  for index in 0..<function.value_count() {
    let value = function.value_at(index).unwrap()
    if allocation.value_location(value) is Some(Register(reg)) {
      record(regs, reg)
    }
  }
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    for operand in 0..<function.instruction_operand_count(instruction) {
      if allocation.operand_location(instruction, operand)
        is Some(Register(reg)) {
        record(regs, reg)
      }
    }
  }
  for edit in allocation.edits() {
    match edit.kind() {
      Spill(reg~, ..) | Reload(reg~, ..) => record(regs, reg)
      Move(from~, to~, ..) => {
        record(regs, from)
        record(regs, to)
      }
      EdgeMove(from~, to~, ..) => {
        if from is Register(reg) {
          record(regs, reg)
        }
        if to is Register(reg) {
          record(regs, reg)
        }
      }
    }
  }
  regs.sort_by(fn(left, right) {
    let class_order = match (left.class, right.class) {
      (Int, FpVector) => -1
      (FpVector, Int) => 1
      _ => 0
    }
    if class_order != 0 {
      class_order
    } else {
      left.id.compare(right.id)
    }
  })
  regs
}

///|
fn maximum_outgoing_args_size(function : @vcode.Function[X64Inst]) -> Int {
  let mut maximum = 0
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    if function.instruction(instruction)
      is Some(
        PlatformCall(_, signature)
        | ReturnsTwicePlatformCall(_, signature)
      ) {
      let size = platform_call_layout(signature.params).stack_size
      if size > maximum {
        maximum = size
      }
    } else if function.instruction(instruction)
      is Some(InternalCall(_, _, plan)) &&
      plan.stack_size > maximum {
      maximum = plan.stack_size
    } else if function.instruction(instruction)
      is Some(InternalCallIndirect(_, plan)) &&
      plan.stack_size > maximum {
      maximum = plan.stack_size
    }
  }
  maximum
}

///|
fn function_has_calls(function : @vcode.Function[X64Inst]) -> Bool {
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    if function.instruction(instruction)
      is Some(
        PlatformCall(_, _)
        | ReturnsTwicePlatformCall(_, _)
        | InternalCall(_, _, _)
        | InternalCallIndirect(_, _)
      ) {
      return true
    }
  }
  false
}

///|
fn maximum_tail_args_size(function : @vcode.Function[X64Inst]) -> Int {
  let mut maximum = incoming_stack_capacity(function)
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    let size = match function.instruction(instruction) {
      Some(TailCallDirect(_, _, plan) | TailCallIndirect(_, plan)) =>
        plan.stack_size
      _ => 0
    }
    if size > maximum {
      maximum = size
    }
  }
  maximum
}

///|
fn maximum_result_area_size(function : @vcode.Function[X64Inst]) -> Int {
  let mut maximum = 0
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    let size = match function.instruction(instruction) {
      Some(InternalCall(_, _, plan) | InternalCallIndirect(_, plan)) =>
        plan.result_area_size
      _ => 0
    }
    if size > maximum {
      maximum = size
    }
  }
  maximum
}

///|
fn stack_object_area_requirements(
  function : @vcode.Function[X64Inst],
) -> (Int, Int)? raise X64FrameError {
  let mut requirements : (Int, Int)? = None
  let objects : Array[X64StackObject] = []
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    if function.instruction(instruction) is Some(StackAddress(object)) {
      if !object.is_valid() {
        raise InvalidStackObjectArea(
          message="invalid stack-object descriptor in target VCode",
        )
      }
      let current = (object.area_size, object.area_alignment)
      match requirements {
        Some(expected) if expected != current =>
          raise InvalidStackObjectArea(
            message="stack-address instructions disagree about the object area",
          )
        None => requirements = Some(current)
        _ => ()
      }
      if !objects.contains(object) {
        for existing in objects {
          if object.offset < existing.offset + existing.size &&
            existing.offset < object.offset + object.size {
            raise InvalidStackObjectArea(
              message="stack objects overlap in the target frame",
            )
          }
        }
        objects.push(object)
      }
    }
  }
  requirements
}

///|
fn moves_require_emergency(
  moves : Array[@vcode.ParallelMove],
) -> Bool raise X64FrameError {
  @vcode.plan_parallel_moves(
    moves,
    int_transfer_scratch(),
    fp_transfer_scratch(),
  ).requires_emergency catch {
    error => raise MovePlanningFailed(cause=error)
  }
}

///|
fn requires_emergency_move_area(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
) -> Bool raise X64FrameError {
  for block in function.layout() {
    for instruction in function.block_body(block) {
      if !is_abi_materialization(function.instruction(instruction).unwrap()) {
        if moves_require_emergency(
            edit_parallel_moves(function, allocation, instruction, Before),
          ) ||
          moves_require_emergency(
            edit_parallel_moves(function, allocation, instruction, After),
          ) {
          return true
        }
      }
    }
    let terminator = function.block_terminator(block).unwrap()
    if moves_require_emergency(
        edit_parallel_moves(function, allocation, terminator, Before),
      ) ||
      moves_require_emergency(
        edit_parallel_moves(function, allocation, terminator, After),
      ) {
      return true
    }
    for successor_index in 0..<function.instruction_successor_count(terminator) {
      if moves_require_emergency(
          edge_parallel_moves(function, allocation, block, successor_index),
        ) {
        return true
      }
    }
  }
  false
}

///|
pub fn X64Frame::frame_size(self : X64Frame) -> Int {
  if self.has_setup_area {
    self.layout.frame_size() + 8
  } else {
    self.layout.frame_size()
  }
}

///|
fn X64Frame::allocation_size(self : X64Frame) -> Int {
  self.layout.frame_size()
}

///|
fn X64Frame::has_setup_area(self : X64Frame) -> Bool {
  self.has_setup_area
}

///|
pub fn X64Frame::incoming_args_size(self : X64Frame) -> Int {
  self.incoming_args_size
}

///|
pub fn X64Frame::tail_args_size(self : X64Frame) -> Int {
  self.tail_args_size
}

///|
fn X64Frame::tail_call_stack_base(
  self : X64Frame,
  callee_args_size : Int,
) -> Int {
  if callee_args_size <= self.incoming_args_size {
    self.frame_size() + 8
  } else {
    self.frame_size() - callee_args_size
  }
}

///|
fn tail_cleanup_area_size(
  incoming_args_size : Int,
  tail_args_size : Int,
) -> Int {
  if tail_args_size > incoming_args_size {
    tail_args_size
  } else {
    0
  }
}

///|
pub fn X64Frame::alignment(self : X64Frame) -> Int {
  self.layout.alignment()
}

///|
pub fn X64Frame::outgoing_args_size(self : X64Frame) -> Int {
  self.outgoing_args_size
}

///|
fn X64Frame::result_area_offset(self : X64Frame) -> Int? {
  self.result_area.map(area => area.offset)
}

///|
pub fn X64Frame::emergency_move_offset(self : X64Frame) -> Int? {
  self.emergency_move_offset
}

///|
pub fn X64Frame::stack_object_offset(
  self : X64Frame,
  object : X64StackObject,
) -> Int? {
  match self.stack_objects {
    Some(area) if object.is_valid() &&
      area.size == object.area_size &&
      area.alignment == object.area_alignment =>
      Some(area.offset + object.offset)
    _ => None
  }
}

///|
pub fn X64Frame::slot_offset(self : X64Frame, slot : @vcode.StackSlot) -> Int? {
  self.layout.slot_offset(slot)
}

///|
pub fn X64Frame::saved_registers(
  self : X64Frame,
) -> Array[(@vcode.PhysicalReg, Int)] {
  self.saved_registers.map(saved => (saved.reg, saved.offset))
}

///|
pub fn X64Frame::summary(self : X64Frame) -> String {
  let mut output = "x64 frame size=\{self.frame_size()} align=\{self.alignment()}\n"
  if self.tail_args_size > self.incoming_args_size {
    output += "  tail-args \{self.tail_args_size} bytes at sp+\{self.local_size} (incoming \{self.incoming_args_size})\n"
  }
  if self.outgoing_args_size > 0 {
    output += "  outgoing \{self.outgoing_args_size} bytes at sp+0\n"
  }
  if self.result_area is Some(area) {
    output += "  call-results \{area.size} bytes at sp+\{area.offset}\n"
  }
  if self.stack_objects is Some(area) {
    output += "  stack-objects \{area.size} bytes at sp+\{area.offset}\n"
  }
  if self.emergency_move_offset is Some(offset) {
    output += "  emergency-move 16 bytes at sp+\{offset}\n"
  }
  for entry in self.slots {
    let (slot, offset) = entry
    output += "  place \{Repr(slot)} at sp+\{offset}\n"
  }
  for saved in self.saved_registers {
    output += "  save \{Repr(saved.reg)} at sp+\{saved.offset}\n"
  }
  output
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
  let expected_outgoing = maximum_outgoing_args_size(function)
  if frame.outgoing_args_size != expected_outgoing {
    raise OutgoingAreaMismatch(
      expected=expected_outgoing,
      actual=frame.outgoing_args_size,
    )
  }
  let expected_incoming = incoming_stack_capacity(function)
  let expected_tail = if function.protocol() == Internal {
    maximum_tail_args_size(function)
  } else {
    expected_incoming
  }
  let expected_tail_area = tail_cleanup_area_size(
    expected_incoming, expected_tail,
  )
  if frame.incoming_args_size != expected_incoming ||
    frame.tail_args_size != expected_tail ||
    frame.local_size + expected_tail_area != frame.allocation_size() {
    raise TailAreaMismatch(
      expected_incoming~,
      actual_incoming=frame.incoming_args_size,
      expected_tail~,
      actual_tail=frame.tail_args_size,
    )
  }
  let expected_result_area = maximum_result_area_size(function)
  let actual_result_area = frame.result_area.map(area => area.size).unwrap_or(0)
  if actual_result_area != expected_result_area {
    raise ResultAreaMismatch(
      expected=expected_result_area,
      actual=actual_result_area,
    )
  }
  if frame.result_area is Some(area) &&
    (
      area.offset < frame.outgoing_args_size ||
      area.offset % 16 != 0 ||
      area.offset + area.size > frame.local_size
    ) {
    raise ResultAreaMismatch(expected=expected_result_area, actual=area.size)
  }
  let expected_stack_objects = stack_object_area_requirements(function)
  let reserved_call_area_end = match frame.result_area {
    Some(area) => area.offset + area.size
    None => frame.outgoing_args_size
  }
  match (expected_stack_objects, frame.stack_objects) {
    (None, None) => ()
    (Some((size, alignment)), Some(area)) =>
      if area.size != size ||
        area.alignment != alignment ||
        area.offset < reserved_call_area_end ||
        area.offset % alignment != 0 ||
        area.offset + size > frame.local_size {
        raise InvalidStackObjectArea(
          message="planned stack-object area does not satisfy target requirements",
        )
      }
    _ =>
      raise InvalidStackObjectArea(
        message="planned stack-object area presence does not match target VCode",
      )
  }
  let reserved_object_area_end = match frame.stack_objects {
    Some(area) => area.offset + area.size
    None => reserved_call_area_end
  }
  let expected_emergency = requires_emergency_move_area(function, allocation)
  match (expected_emergency, frame.emergency_move_offset) {
    (false, None) => ()
    (true, Some(offset)) =>
      if offset < reserved_object_area_end ||
        offset % 16 != 0 ||
        offset + 16 > frame.local_size {
        raise InvalidEmergencyMoveArea(offset=Some(offset))
      }
    _ => raise InvalidEmergencyMoveArea(offset=frame.emergency_move_offset)
  }
  let expected = used_callee_saved_registers(function, allocation)
  if frame.saved_registers.map(saved => saved.reg) != expected {
    raise SavedRegisterSetMismatch
  }
  let occupied : Array[(Int, Int)] = []
  if frame.outgoing_args_size > 0 {
    occupied.push((0, frame.outgoing_args_size))
  }
  if frame.result_area is Some(area) {
    occupied.push((area.offset, area.offset + area.size))
  }
  if frame.stack_objects is Some(area) {
    occupied.push((area.offset, area.offset + area.size))
  }
  if frame.emergency_move_offset is Some(offset) {
    occupied.push((offset, offset + 16))
  }
  for index in 0..<allocation.stack_slot_count() {
    let slot = allocation.stack_slot_at(index).unwrap()
    let offset = frame.slot_offset(slot).unwrap()
    if offset + allocation.stack_slot_size(slot).unwrap() > frame.local_size {
      raise InvalidStackSlot(slot~)
    }
    occupied.push((offset, offset + allocation.stack_slot_size(slot).unwrap()))
  }
  for saved in frame.saved_registers {
    let size = register_save_size(saved.reg)
    if saved.offset < 0 ||
      saved.offset % size != 0 ||
      saved.offset + size > frame.local_size {
      raise InvalidSavedRegister(reg=saved.reg, offset=saved.offset)
    }
    for range in occupied {
      if saved.offset < range.1 && range.0 < saved.offset + size {
        raise InvalidSavedRegister(reg=saved.reg, offset=saved.offset)
      }
    }
    occupied.push((saved.offset, saved.offset + size))
  }
}

///|
fn plan_frame_verified(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
) -> X64Frame raise X64FrameError {
  let outgoing_args_size = maximum_outgoing_args_size(function)
  let mut offset = outgoing_args_size
  let result_area_size = maximum_result_area_size(function)
  let result_area = if result_area_size > 0 {
    offset = align_up(offset, 16)
    let area = { offset, size: result_area_size, }
    offset += result_area_size
    Some(area)
  } else {
    None
  }
  let stack_objects = match stack_object_area_requirements(function) {
    Some((size, alignment)) => {
      offset = align_up(offset, alignment)
      let area = { offset, size, alignment, }
      offset += size
      Some(area)
    }
    None => None
  }
  let emergency_move_offset = if requires_emergency_move_area(
      function, allocation,
    ) {
    offset = align_up(offset, 16)
    let emergency_offset = offset
    offset += 16
    Some(emergency_offset)
  } else {
    None
  }
  let slot_offsets : Array[Int] = []
  for index in 0..<allocation.stack_slot_count() {
    let slot = allocation.stack_slot_at(index).unwrap()
    let alignment = allocation.stack_slot_alignment(slot).unwrap()
    offset = align_up(offset, alignment)
    slot_offsets.push(offset)
    offset += allocation.stack_slot_size(slot).unwrap()
  }
  let saved_registers : Array[SavedRegister] = []
  for reg in used_callee_saved_registers(function, allocation) {
    let size = register_save_size(reg)
    offset = align_up(offset, size)
    saved_registers.push({ reg, offset, })
    offset += size
  }
  let local_size = align_up(offset, 16)
  let incoming_args_size = incoming_stack_capacity(function)
  let tail_args_size = if function.protocol() == Internal {
    maximum_tail_args_size(function)
  } else {
    incoming_args_size
  }
  let tail_area_size = tail_cleanup_area_size(
    incoming_args_size, tail_args_size,
  )
  let allocation_size = local_size + tail_area_size
  let layout = @vcode.FrameLayout::new(
    function, allocation, allocation_size, 16,
  )
  for index, slot_offset in slot_offsets {
    layout.place_slot(allocation.stack_slot_at(index).unwrap(), slot_offset)
    |> ignore
  }
  let slots = Array::makei(slot_offsets.length(), index => {
    (allocation.stack_slot_at(index).unwrap(), slot_offsets[index])
  })
  let frame = {
    layout,
    has_setup_area: allocation_size > 0 || function_has_calls(function),
    local_size,
    incoming_args_size,
    tail_args_size,
    outgoing_args_size,
    result_area,
    stack_objects,
    emergency_move_offset,
    slots,
    saved_registers,
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
