///|
pub(all) enum StackSlotKind {
  Spill(VirtualReg)
  Local(Int)
  OutgoingArg(Int)
  CalleeSaved(PhysicalReg)
} derive(Eq, Debug)

///|
fn StackSlotKind::to_string(self : StackSlotKind) -> String {
  match self {
    Spill(vreg) => "spill(\{vreg_to_string(vreg)})"
    Local(idx) => "local\{idx}"
    OutgoingArg(idx) => "arg\{idx}"
    CalleeSaved(preg) => "saved(\{preg_to_string(preg)})"
  }
}

///|
pub impl Show for StackSlotKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) struct StackSlot {
  offset : Int
  size : Int
  align : Int
  kind : StackSlotKind
} derive(Eq, Debug)

///|
fn StackSlot::to_string(self : StackSlot) -> String {
  let sign = if self.offset >= 0 { "+" } else { "" }
  "[fp\{sign}\{self.offset}] \{self.kind} (\{self.size}B, align \{self.align})"
}

///|
pub impl Show for StackSlot with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) struct StackFrame {
  slots : Array[StackSlot]
  mut frame_size : Int
  frame_align : Int
  mut next_spill_offset : Int
  mut next_arg_offset : Int
  callee_saved_regs : Array[PhysicalReg]
}

///|
pub fn StackFrame::new(frame_align : Int) -> StackFrame {
  {
    slots: [],
    frame_size: 0,
    frame_align,
    next_spill_offset: 0,
    next_arg_offset: 0,
    callee_saved_regs: [],
  }
}

///|
pub fn StackFrame::alloc_spill_slot(
  self : StackFrame,
  vreg : VirtualReg,
  size : Int,
  align : Int,
) -> Int {
  let aligned_offset = align_up(self.next_spill_offset, align)
  let slot = StackSlot::{
    offset: -aligned_offset - size,
    size,
    align,
    kind: Spill(vreg),
  }
  self.slots.push(slot)
  self.next_spill_offset = aligned_offset + size
  slot.offset
}

///|
pub fn StackFrame::alloc_local(
  self : StackFrame,
  local_idx : Int,
  size : Int,
  align : Int,
) -> Int {
  let aligned_offset = align_up(self.next_spill_offset, align)
  let slot = StackSlot::{
    offset: -aligned_offset - size,
    size,
    align,
    kind: Local(local_idx),
  }
  self.slots.push(slot)
  self.next_spill_offset = aligned_offset + size
  slot.offset
}

///|
pub fn StackFrame::alloc_outgoing_arg(
  self : StackFrame,
  arg_idx : Int,
  size : Int,
  align : Int,
) -> Int {
  let aligned_offset = align_up(self.next_arg_offset, align)
  let slot = StackSlot::{
    offset: aligned_offset,
    size,
    align,
    kind: OutgoingArg(arg_idx),
  }
  self.slots.push(slot)
  self.next_arg_offset = aligned_offset + size
  slot.offset
}

///|
pub fn StackFrame::add_callee_saved(
  self : StackFrame,
  preg : PhysicalReg,
) -> Int {
  let size = 8
  let align = 8
  let aligned_offset = align_up(self.next_spill_offset, align)
  let slot = StackSlot::{
    offset: -aligned_offset - size,
    size,
    align,
    kind: CalleeSaved(preg),
  }
  self.slots.push(slot)
  self.callee_saved_regs.push(preg)
  self.next_spill_offset = aligned_offset + size
  slot.offset
}

///|
pub fn StackFrame::finalize(self : StackFrame) -> Unit {
  let spill_size = self.next_spill_offset
  let arg_size = self.next_arg_offset
  self.frame_size = align_up(spill_size + arg_size, self.frame_align)
}

///|
pub fn StackFrame::size(self : StackFrame) -> Int {
  self.frame_size
}

///|
pub fn StackFrame::get_callee_saved(self : StackFrame) -> Array[PhysicalReg] {
  self.callee_saved_regs
}

///|
pub fn StackFrame::print(self : StackFrame) -> String {
  let mut result = "Stack Frame (size=\{self.frame_size}, align=\{self.frame_align}):\n"
  for slot in self.slots {
    result = result + "  \{slot}\n"
  }
  if self.callee_saved_regs.length() > 0 {
    result = result + "Callee-saved: "
    for i, preg in self.callee_saved_regs {
      if i > 0 {
        result = result + ", "
      }
      result = result + preg_to_string(preg)
    }
    result = result + "\n"
  }
  result
}

///|
pub impl Show for StackFrame with fn output(self, logger) {
  logger.write_string(self.print())
}

///|
fn align_up(value : Int, align : Int) -> Int {
  if align <= 1 {
    value
  } else {
    (value + align - 1) / align * align
  }
}

///|
fn vreg_to_string(vreg : VirtualReg) -> String {
  let prefix = match vreg.class {
    Int => "v"
    Float => "f"
    Vector => "vec"
  }
  "\{prefix}\{vreg.id}"
}

///|
fn preg_to_string(preg : PhysicalReg) -> String {
  let prefix = match preg.class {
    Int => "x"
    Float => "f"
    Vector => "v"
  }
  "\{prefix}\{preg.id}"
}
