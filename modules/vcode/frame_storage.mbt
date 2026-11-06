///|
priv struct FrameStackObjects {
  offset : Int32
  size : Int32
  alignment : Int32
}

///|
priv struct FrameResultArea {
  offset : Int32
  size : Int32
}

///|
/// The local frame areas shared by targets. Incoming arguments, tail-call
/// staging and frame records are planned by the target ABI.
pub struct FrameStorage {
  priv local_size : Int32
  priv result_area : FrameResultArea?
  priv stack_objects : FrameStackObjects?
  priv stack_object_offsets : Array[Int32]
  priv emergency_move_offset : Int32?
  priv requires_emergency_moves : Bool
  priv slots : Array[(StackSlot, Int32)]
  priv saved_registers : Array[(PhysicalReg, Int32)]
}

///|
pub(all) suberror FrameStorageError {
  InvalidSavedRegister(reg~ : PhysicalReg, offset~ : Int32)
  InvalidStackSlot(slot~ : StackSlot)
  ResultAreaMismatch(expected~ : Int32, actual~ : Int32)
  InvalidStackObjectArea(message~ : String)
  InvalidEmergencyMoveArea(offset~ : Int32?)
  SavedRegisterSetMismatch
}

///|
pub fn FrameStorage::plan(
  requirements : FrameRequirements,
  allocation : Allocation,
  requires_emergency_moves : Bool,
  saved : Array[PhysicalReg],
) -> FrameStorage {
  let outgoing_args_size = requirements.outgoing_args_size
  let mut offset = outgoing_args_size
  let result_area_size = requirements.result_area_size
  let result_area = if result_area_size > 0 {
    offset = align_frame_area(offset, 16)
    let area = { offset, size: result_area_size, }
    offset += result_area_size
    Some(area)
  } else {
    None
  }
  let stack_object_requirements = requirements.stack_objects
  let stack_objects = match stack_object_requirements {
    Some(requirements) => {
      offset = align_frame_area(offset, requirements.alignment)
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
  let emergency_move_offset = if requires_emergency_moves {
    offset = align_frame_area(offset, 16)
    let emergency_offset = offset
    offset += 16
    Some(emergency_offset)
  } else {
    None
  }
  let slots = Array::makei(allocation.stack_slot_count(), index => {
    let slot = allocation.stack_slot_at(index).unwrap()
    offset = align_frame_area(
      offset,
      allocation.stack_slot_alignment(slot).unwrap(),
    )
    let placement = (slot, offset)
    offset += allocation.stack_slot_size(slot).unwrap()
    placement
  })
  let saved_registers = saved.map(reg => {
    let size = 8
    offset = align_frame_area(offset, size)
    let placement = (reg, offset)
    offset += size
    placement
  })
  {
    local_size: align_frame_area(offset, 16),
    result_area,
    stack_objects,
    stack_object_offsets: stack_object_requirements
    .map(req => req.offsets)
    .unwrap_or([]),
    emergency_move_offset,
    requires_emergency_moves,
    slots,
    saved_registers,
  }
}

///|
pub fn FrameStorage::local_size(self : FrameStorage) -> Int32 {
  self.local_size
}

///|
pub fn FrameStorage::result_area_offset(self : FrameStorage) -> Int32? {
  self.result_area.map(area => area.offset)
}

///|
pub fn FrameStorage::stack_object_offset(
  self : FrameStorage,
  id : Int32,
) -> Int32? {
  match self.stack_objects {
    Some(area) if id >= 0 && id < self.stack_object_offsets.length() =>
      Some(area.offset + self.stack_object_offsets[id])
    _ => None
  }
}

///|
pub fn FrameStorage::emergency_move_offset(self : FrameStorage) -> Int32? {
  self.emergency_move_offset
}

///|
pub fn FrameStorage::saved_registers(
  self : FrameStorage,
) -> Array[(PhysicalReg, Int32)] {
  self.saved_registers.copy()
}

///|
pub fn FrameStorage::place_slots(
  self : FrameStorage,
  layout : FrameLayout,
) -> Unit {
  for placement in self.slots {
    let (slot, offset) = placement
    ignore(layout.place_slot(slot, offset))
  }
}

///|
pub fn FrameStorage::verify(
  self : FrameStorage,
  layout : FrameLayout,
  allocation : Allocation,
  requirements : FrameRequirements,
  expected_saved : Array[PhysicalReg],
) -> Unit raise FrameStorageError {
  let expected_result_area = requirements.result_area_size
  let actual_result_area = self.result_area.map(area => area.size).unwrap_or(0)
  if actual_result_area != expected_result_area {
    raise ResultAreaMismatch(
      expected=expected_result_area,
      actual=actual_result_area,
    )
  }
  if self.result_area is Some(area) &&
    (
      area.offset < requirements.outgoing_args_size ||
      area.offset % 16 != 0 ||
      area.offset + area.size > self.local_size
    ) {
    raise ResultAreaMismatch(expected=expected_result_area, actual=area.size)
  }
  let expected_stack_objects = requirements.stack_objects
  let reserved_call_area_end = match self.result_area {
    Some(area) => area.offset + area.size
    None => requirements.outgoing_args_size
  }
  match (expected_stack_objects, self.stack_objects) {
    (None, None) => ()
    (Some(requirements), Some(area)) =>
      if area.size != requirements.size ||
        area.alignment != requirements.alignment ||
        area.offset < reserved_call_area_end ||
        area.offset % requirements.alignment != 0 ||
        area.offset + requirements.size > self.local_size ||
        self.stack_object_offsets != requirements.offsets {
        raise InvalidStackObjectArea(
          message="planned stack-object area does not satisfy target requirements",
        )
      }
    _ =>
      raise InvalidStackObjectArea(
        message="planned stack-object area presence does not match target VCode",
      )
  }
  let reserved_object_area_end = match self.stack_objects {
    Some(area) => area.offset + area.size
    None => reserved_call_area_end
  }
  match (self.requires_emergency_moves, self.emergency_move_offset) {
    (false, None) => ()
    (true, Some(offset)) =>
      if offset < reserved_object_area_end ||
        offset % 16 != 0 ||
        offset + 16 > self.local_size {
        raise InvalidEmergencyMoveArea(offset=Some(offset))
      }
    _ => raise InvalidEmergencyMoveArea(offset=self.emergency_move_offset)
  }
  if self.saved_registers.map(saved => saved.0) != expected_saved {
    raise SavedRegisterSetMismatch
  }
  let occupied : Array[(Int32, Int32)] = []
  if requirements.outgoing_args_size > 0 {
    occupied.push((0, requirements.outgoing_args_size))
  }
  if self.result_area is Some(area) {
    occupied.push((area.offset, area.offset + area.size))
  }
  if self.stack_objects is Some(area) {
    occupied.push((area.offset, area.offset + area.size))
  }
  if self.emergency_move_offset is Some(offset) {
    occupied.push((offset, offset + 16))
  }
  for index in 0..<allocation.stack_slot_count() {
    let slot = allocation.stack_slot_at(index).unwrap()
    let offset = layout.slot_offset(slot).unwrap()
    if offset + allocation.stack_slot_size(slot).unwrap() > self.local_size {
      raise InvalidStackSlot(slot~)
    }
    occupied.push((offset, offset + allocation.stack_slot_size(slot).unwrap()))
  }
  for saved in self.saved_registers {
    let (reg, offset) = saved
    let size = 8
    if offset < 0 || offset % size != 0 || offset + size > self.local_size {
      raise InvalidSavedRegister(reg~, offset~)
    }
    for range in occupied {
      if offset < range.1 && range.0 < offset + size {
        raise InvalidSavedRegister(reg~, offset~)
      }
    }
    occupied.push((offset, offset + size))
  }
}

///|
pub fn FrameStorage::summary(
  self : FrameStorage,
  outgoing_args_size : Int32,
) -> String {
  let mut output = ""
  if outgoing_args_size > 0 {
    output += "  outgoing \{outgoing_args_size} bytes at sp+0\n"
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
    output += "  save \{Repr(saved.0)} at sp+\{saved.1}\n"
  }
  output
}
