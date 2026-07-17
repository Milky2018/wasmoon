///|
priv struct SavedRegister {
  reg : @vcode.PhysicalReg
  offset : Int
}

///|
pub struct AArch64Frame {
  priv layout : @vcode.FrameLayout
  priv slots : Array[(@vcode.StackSlot, Int)]
  priv saved_registers : Array[SavedRegister]
}

///|
pub suberror AArch64FrameError {
  InvalidAllocation(cause~ : AArch64AllocationError)
  InvalidGenericFrame(cause~ : @vcode.FrameVerifyError)
  InvalidSavedRegister(reg~ : @vcode.PhysicalReg, offset~ : Int)
  SavedRegisterSetMismatch
} derive(Debug)

///|
pub impl Show for AArch64FrameError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn is_callee_saved(reg : @vcode.PhysicalReg) -> Bool {
  match reg.class {
    Int => reg.id >= 19 && reg.id <= 28
    FpVector => reg.id >= 8 && reg.id <= 15
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
  for index in 0..<function.value_count() {
    let value = function.value_at(index).unwrap()
    if allocation.value_location(value) is Some(Register(reg)) &&
      is_callee_saved(reg) &&
      !regs.contains(reg) {
      regs.push(reg)
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
pub fn AArch64Frame::frame_size(self : AArch64Frame) -> Int {
  self.layout.frame_size()
}

///|
pub fn AArch64Frame::alignment(self : AArch64Frame) -> Int {
  self.layout.alignment()
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
  for entry in self.slots {
    let (slot, offset) = entry
    output += "  place \{to_repr(slot)} at sp+\{offset}\n"
  }
  for saved in self.saved_registers {
    output += "  save \{to_repr(saved.reg)} at sp+\{saved.offset}\n"
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
  let expected = used_callee_saved_registers(function, allocation)
  if frame.saved_registers.map(saved => saved.reg) != expected {
    raise SavedRegisterSetMismatch
  }
  let occupied : Array[(Int, Int)] = []
  for index in 0..<allocation.stack_slot_count() {
    let slot = allocation.stack_slot_at(index).unwrap()
    let offset = frame.slot_offset(slot).unwrap()
    occupied.push((offset, offset + allocation.stack_slot_size(slot).unwrap()))
  }
  for saved in frame.saved_registers {
    let size = register_save_size(saved.reg)
    if saved.offset < 0 ||
      saved.offset % size != 0 ||
      saved.offset + size > frame.frame_size() {
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
pub fn plan_frame(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
) -> AArch64Frame raise AArch64FrameError {
  verify_allocation(function, allocation) catch {
    error => raise InvalidAllocation(cause=error)
  }
  let mut offset = 0
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
    saved_registers.push({ reg, offset })
    offset += size
  }
  let layout = @vcode.FrameLayout::new(
    function,
    allocation,
    align_up(offset, 16),
    16,
  )
  for index, slot_offset in slot_offsets {
    layout.place_slot(allocation.stack_slot_at(index).unwrap(), slot_offset)
    |> ignore
  }
  let slots = Array::makei(slot_offsets.length(), index => {
    (allocation.stack_slot_at(index).unwrap(), slot_offsets[index])
  })
  let frame = { layout, slots, saved_registers }
  verify_frame(function, allocation, frame)
  frame
}
