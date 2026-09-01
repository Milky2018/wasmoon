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
priv struct StackObjectRequirements {
  size : Int
  alignment : Int
  offsets : Array[Int]
}

///|
pub struct AArch64Frame {
  priv layout : @vcode.FrameLayout
  priv local_size : Int
  priv incoming_args_size : Int
  priv tail_args_size : Int
  priv outgoing_args_size : Int
  priv result_area : ResultArea?
  priv stack_objects : StackObjectArea?
  priv stack_object_offsets : Array[Int]
  priv emergency_move_offset : Int?
  priv requires_emergency_moves : Bool
  priv allocation_edit_count : Int
  priv slots : Array[(@vcode.StackSlot, Int)]
  priv saved_registers : Array[SavedRegister]
}

///|
pub suberror AArch64FrameError {
  InvalidAllocation(cause~ : AArch64AllocationError)
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
  StaleAllocation(expected_edits~ : Int, actual_edits~ : Int)
  SavedRegisterSetMismatch
} derive(Debug)

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
fn register_save_size(reg : @vcode.PhysicalReg) -> Int {
  ignore(reg)
  8
}

///|
fn used_callee_saved_registers(
  function : @vcode.Function[AArch64Inst],
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
    let location = allocation.allocated_value_location_at(index).unwrap()
    if location.is_register() {
      record(regs, location.register_unchecked())
    }
  }
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    for operand in 0..<function.instruction_operand_count(instruction) {
      let location = allocation
        .allocated_operand_location_at(index, operand)
        .unwrap()
      if location.is_register() {
        record(regs, location.register_unchecked())
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
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    if function.instruction(instruction)
      is Some(
        PlatformCall(_, _)
        | ReturnsTwicePlatformCall(_, _)
        | InternalCall(_, _, _)
        | InternalCallIndirect(_, _)
      ) {
      let link_register = @vcode.PhysicalReg::new(30, Int)
      if !regs.contains(link_register) {
        regs.push(link_register)
      }
      break
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
fn maximum_outgoing_args_size(function : @vcode.Function[AArch64Inst]) -> Int {
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
fn maximum_tail_args_size(function : @vcode.Function[AArch64Inst]) -> Int {
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
fn maximum_result_area_size(function : @vcode.Function[AArch64Inst]) -> Int {
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
  function : @vcode.Function[AArch64Inst],
) -> StackObjectRequirements? raise AArch64FrameError {
  let objects : Array[AArch64StackObject?] = []
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    if function.instruction(instruction) is Some(StackAddress(object)) {
      if !object.is_valid() {
        raise InvalidStackObjectArea(
          message="invalid stack-object descriptor in target VCode",
        )
      }
      while objects.length() <= object.id {
        objects.push(None)
      }
      match objects[object.id] {
        Some(existing) if existing != object =>
          raise InvalidStackObjectArea(
            message="stack-object id has conflicting size or alignment",
          )
        None => objects[object.id] = Some(object)
        _ => ()
      }
    }
  }
  if objects.is_empty() {
    return None
  }
  let offsets : Array[Int] = []
  let mut cursor = 0
  let mut area_alignment = 1
  for object in objects {
    guard object is Some(object) else {
      raise InvalidStackObjectArea(
        message="stack-object ids must be dense within one function",
      )
    }
    cursor = align_up(cursor, object.alignment)
    offsets.push(cursor)
    cursor += object.size
    if object.alignment > area_alignment {
      area_alignment = object.alignment
    }
  }
  Some({
    size: align_up(cursor, area_alignment),
    alignment: area_alignment,
    offsets,
  })
}

///|
fn moves_require_emergency(
  moves : Array[@vcode.ParallelMove],
) -> Bool raise AArch64FrameError {
  @vcode.plan_parallel_moves(
    moves,
    int_transfer_scratch(),
    fp_transfer_scratch(),
  ).requires_emergency catch {
    error => raise MovePlanningFailed(cause=error)
  }
}

///|
fn instruction_edits_require_emergency(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  instruction : @vcode.Instruction,
  placement : @vcode.PointPlacement,
) -> Bool raise AArch64FrameError {
  if allocation.edits_at(instruction, placement).is_empty() {
    return false
  }
  moves_require_emergency(
    edit_parallel_moves(function, allocation, instruction, placement),
  )
}

///|
fn edge_edits_require_emergency(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  block : @vcode.Block,
  successor_index : Int,
) -> Bool raise AArch64FrameError {
  if allocation.edge_edits_at(block, successor_index).is_empty() {
    return false
  }
  moves_require_emergency(
    edge_parallel_moves(function, allocation, block, successor_index),
  )
}

///|
fn requires_emergency_move_area(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
) -> Bool raise AArch64FrameError {
  for block in function.layout() {
    for instruction in function.block_body(block) {
      if !is_abi_materialization(function.instruction(instruction).unwrap()) {
        if instruction_edits_require_emergency(
            function,
            allocation,
            instruction,
            Before,
          ) ||
          instruction_edits_require_emergency(
            function,
            allocation,
            instruction,
            After,
          ) {
          return true
        }
      }
    }
    let terminator = function.block_terminator(block).unwrap()
    if instruction_edits_require_emergency(
        function,
        allocation,
        terminator,
        Before,
      ) ||
      instruction_edits_require_emergency(
        function,
        allocation,
        terminator,
        After,
      ) {
      return true
    }
    for successor_index in 0..<function.instruction_successor_count(terminator) {
      if edge_edits_require_emergency(
          function, allocation, block, successor_index,
        ) {
        return true
      }
    }
  }
  false
}

///|
pub fn AArch64Frame::frame_size(self : AArch64Frame) -> Int {
  self.layout.frame_size()
}

///|
pub fn AArch64Frame::incoming_args_size(self : AArch64Frame) -> Int {
  self.incoming_args_size
}

///|
pub fn AArch64Frame::tail_args_size(self : AArch64Frame) -> Int {
  self.tail_args_size
}

///|
fn AArch64Frame::tail_call_stack_base(
  self : AArch64Frame,
  callee_args_size : Int,
) -> Int {
  if callee_args_size <= self.incoming_args_size {
    self.frame_size()
  } else {
    self.frame_size() - callee_args_size - 16
  }
}

///|
fn tail_cleanup_area_size(
  incoming_args_size : Int,
  tail_args_size : Int,
) -> Int {
  if tail_args_size > incoming_args_size {
    tail_args_size + 16
  } else {
    0
  }
}

///|
pub fn AArch64Frame::alignment(self : AArch64Frame) -> Int {
  self.layout.alignment()
}

///|
pub fn AArch64Frame::outgoing_args_size(self : AArch64Frame) -> Int {
  self.outgoing_args_size
}

///|
fn AArch64Frame::result_area_offset(self : AArch64Frame) -> Int? {
  self.result_area.map(area => area.offset)
}

///|
pub fn AArch64Frame::emergency_move_offset(self : AArch64Frame) -> Int? {
  self.emergency_move_offset
}

///|
pub fn AArch64Frame::stack_object_offset(
  self : AArch64Frame,
  object : AArch64StackObject,
) -> Int? {
  match self.stack_objects {
    Some(area) if object.is_valid() &&
      object.id < self.stack_object_offsets.length() =>
      Some(area.offset + self.stack_object_offsets[object.id])
    _ => None
  }
}

///|
pub fn AArch64Frame::slot_offset(
  self : AArch64Frame,
  slot : @vcode.StackSlot,
) -> Int? {
  self.layout.slot_offset(slot)
}

///|
pub fn AArch64Frame::saved_registers(
  self : AArch64Frame,
) -> Array[(@vcode.PhysicalReg, Int)] {
  self.saved_registers.map(saved => (saved.reg, saved.offset))
}

///|
pub fn AArch64Frame::summary(self : AArch64Frame) -> String {
  let mut output = "aarch64 frame size=\{self.frame_size()} align=\{self.alignment()}\n"
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
    frame.local_size + expected_tail_area != frame.frame_size() {
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
    (Some(requirements), Some(area)) =>
      if area.size != requirements.size ||
        area.alignment != requirements.alignment ||
        area.offset < reserved_call_area_end ||
        area.offset % requirements.alignment != 0 ||
        area.offset + requirements.size > frame.local_size ||
        frame.stack_object_offsets != requirements.offsets {
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
  match (frame.requires_emergency_moves, frame.emergency_move_offset) {
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
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
) -> AArch64Frame raise AArch64FrameError {
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
  let stack_object_requirements = stack_object_area_requirements(function)
  let stack_objects = match stack_object_requirements {
    Some(requirements) => {
      offset = align_up(offset, requirements.alignment)
      let area = {
        offset,
        size: requirements.size,
        alignment: requirements.alignment,
      }
      offset += requirements.size
      Some(area)
    }
    None => None
  }
  let requires_emergency_moves = requires_emergency_move_area(
    function, allocation,
  )
  let emergency_move_offset = if requires_emergency_moves {
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
  let layout = @vcode.FrameLayout::new(
    function,
    allocation,
    local_size + tail_area_size,
    16,
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
    local_size,
    incoming_args_size,
    tail_args_size,
    outgoing_args_size,
    result_area,
    stack_objects,
    stack_object_offsets: stack_object_requirements
    .map(requirements => requirements.offsets)
    .unwrap_or([]),
    emergency_move_offset,
    requires_emergency_moves,
    allocation_edit_count: allocation.edit_count(),
    slots,
    saved_registers,
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
