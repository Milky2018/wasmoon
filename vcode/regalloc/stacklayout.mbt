// Stack Layout
// Manages stack frame layout for function calls and spilled registers
//
// This module provides:
// 1. Stack frame layout computation
// 2. Spill slot allocation
// 3. Caller/callee-saved register handling
// 4. Stack pointer adjustment

// ============ Stack Slot ============

///|
/// A stack slot - a location on the stack
struct StackSlot {
  // Offset from frame pointer (negative = below FP, positive = above FP)
  offset : Int
  // Size in bytes
  size : Int
  // Alignment requirement
  align : Int
  // What the slot is used for
  kind : StackSlotKind
}

///|
/// Kind of stack slot
pub enum StackSlotKind {
  // Spilled register
  Spill(@abi.VReg)
  // Local variable
  Local(Int) // Local index
  // Outgoing argument (for calls)
  OutgoingArg(Int) // Argument index
  // Saved callee-saved register
  CalleeSaved(@abi.PReg)
}

///|
fn StackSlotKind::to_string(self : StackSlotKind) -> String {
  match self {
    Spill(vreg) => "spill(\{vreg})"
    Local(idx) => "local\{idx}"
    OutgoingArg(idx) => "arg\{idx}"
    CalleeSaved(preg) => "saved(\{preg})"
  }
}

///|
pub impl Show for StackSlotKind with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
fn StackSlot::to_string(self : StackSlot) -> String {
  let sign = if self.offset >= 0 { "+" } else { "" }
  "[fp\{sign}\{self.offset}] \{self.kind} (\{self.size}B, align \{self.align})"
}

///|
pub impl Show for StackSlot with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Stack Frame ============

///|
/// Stack frame layout for a function
struct StackFrame {
  // All stack slots
  slots : Array[StackSlot]
  // Total frame size (must be aligned)
  mut frame_size : Int
  // Required alignment for the frame
  frame_align : Int
  // Offset for the next spill slot
  mut next_spill_offset : Int
  // Offset for the next outgoing arg
  mut next_arg_offset : Int
  // Callee-saved registers used in this function
  callee_saved_regs : Array[@abi.PReg]
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
/// Allocate a spill slot for a virtual register
pub fn StackFrame::alloc_spill_slot(
  self : StackFrame,
  vreg : @abi.VReg,
  size : Int,
  align : Int,
) -> Int {
  // Align the offset
  let aligned_offset = align_up(self.next_spill_offset, align)
  let slot = StackSlot::{
    offset: -aligned_offset - size, // Negative = below FP
    size,
    align,
    kind: Spill(vreg),
  }
  self.slots.push(slot)
  self.next_spill_offset = aligned_offset + size
  slot.offset
}

///|
/// Allocate a slot for a local variable
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
/// Allocate a slot for an outgoing argument
pub fn StackFrame::alloc_outgoing_arg(
  self : StackFrame,
  arg_idx : Int,
  size : Int,
  align : Int,
) -> Int {
  let aligned_offset = align_up(self.next_arg_offset, align)
  let slot = StackSlot::{
    offset: aligned_offset, // Positive = above current SP for outgoing args
    size,
    align,
    kind: OutgoingArg(arg_idx),
  }
  self.slots.push(slot)
  self.next_arg_offset = aligned_offset + size
  slot.offset
}

///|
/// Record a callee-saved register that needs to be saved
pub fn StackFrame::add_callee_saved(self : StackFrame, preg : @abi.PReg) -> Int {
  let size = 8 // 64-bit registers
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
/// Finalize the frame layout and compute total size
pub fn StackFrame::finalize(self : StackFrame) -> Unit {
  // Frame size is the larger of spill area and outgoing arg area
  let spill_size = self.next_spill_offset
  let arg_size = self.next_arg_offset

  // Total size includes both areas
  let total = spill_size + arg_size

  // Align to frame alignment
  self.frame_size = align_up(total, self.frame_align)
}

///|
/// Get the total frame size
pub fn StackFrame::size(self : StackFrame) -> Int {
  self.frame_size
}

///|
/// Get all callee-saved registers that were used
pub fn StackFrame::get_callee_saved(self : StackFrame) -> Array[@abi.PReg] {
  self.callee_saved_regs
}

///|
/// Print the frame layout
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
      result = result + preg.to_string()
    }
    result = result + "\n"
  }
  result
}

///|
pub impl Show for StackFrame with output(self, logger) {
  logger.write_string(self.print())
}

// ============ Helper Functions ============

///|
fn align_up(value : Int, align : Int) -> Int {
  (value + align - 1) & -align
}

// ============ AArch64 Stack Frame ============

///|
/// AArch64-specific stack frame configuration
struct AArch64StackFrame {
  frame : StackFrame
  // Whether to use frame pointer
  use_fp : Bool
  // Link register save slot
  mut lr_slot : Int?
  // Frame pointer save slot
  mut fp_slot : Int?
}

///|
pub fn AArch64StackFrame::new() -> AArch64StackFrame {
  {
    frame: StackFrame::new(16), // AArch64 requires 16-byte stack alignment
    use_fp: true, // Always use frame pointer for simplicity
    lr_slot: None,
    fp_slot: None,
  }
}

///|
/// Setup the frame with FP and LR saves
pub fn AArch64StackFrame::setup(self : AArch64StackFrame) -> Unit {
  if self.use_fp {
    // Save FP and LR at the top of the frame
    // On AArch64, FP and LR are typically saved together
    let fp_preg : @abi.PReg = { index: 29, class: Int } // x29 = FP
    let lr_preg : @abi.PReg = { index: 30, class: Int } // x30 = LR
    self.fp_slot = Some(self.frame.add_callee_saved(fp_preg))
    self.lr_slot = Some(self.frame.add_callee_saved(lr_preg))
  }
}

///|
/// Allocate a spill slot
pub fn AArch64StackFrame::alloc_spill(
  self : AArch64StackFrame,
  vreg : @abi.VReg,
) -> Int {
  // Size based on register class
  // Note: Float32 values are promoted to f64 internally, so they also use 8 bytes
  let size = match vreg.class {
    Int => 8 // 64-bit
    Float32 | Float64 => 8 // 64-bit (all floats stored as f64)
    Vector => 16 // 128-bit SIMD vector
  }
  self.frame.alloc_spill_slot(vreg, size, size)
}

///|
/// Add a callee-saved register
pub fn AArch64StackFrame::save_callee_reg(
  self : AArch64StackFrame,
  preg : @abi.PReg,
) -> Int {
  self.frame.add_callee_saved(preg)
}

///|
/// Finalize the frame
pub fn AArch64StackFrame::finalize(self : AArch64StackFrame) -> Unit {
  self.frame.finalize()
}

///|
/// Get frame size
pub fn AArch64StackFrame::size(self : AArch64StackFrame) -> Int {
  self.frame.size()
}

///|
/// Generate prologue instructions
pub fn AArch64StackFrame::gen_prologue(
  self : AArch64StackFrame,
) -> Array[@instr.VCodeInst] {
  let insts : Array[@instr.VCodeInst] = []
  let frame_size = self.frame.size()
  if frame_size == 0 {
    return insts
  }

  // STP x29, x30, [sp, #-frame_size]!  (save FP and LR, adjust SP)
  // MOV x29, sp  (set up frame pointer)

  // For now, emit pseudo-instructions that represent the prologue
  // The actual encoding will be done in the code generation phase

  // Adjust stack pointer: SUB sp, sp, #frame_size
  // We represent this as a Sub instruction with the SP as both src and dest
  // Stack pointer operations are always 64-bit
  let sub_sp = @instr.VCodeInst::new(Sub(true))
  sub_sp.add_def({ reg: Physical({ index: 31, class: Int }) }) // SP
  sub_sp.add_use(Physical({ index: 31, class: Int })) // SP
  // The immediate is encoded in the opcode, use LoadConst to represent it
  insts.push(sub_sp)

  // Save FP and LR if using frame pointer
  if self.use_fp && (self.fp_slot, self.lr_slot) is (Some(fp_off), Some(lr_off)) {
    // Store FP
    let store_fp = @instr.VCodeInst::new(Store(I64, fp_off))
    store_fp.add_use(Physical({ index: 29, class: Int })) // FP
    store_fp.add_use(Physical({ index: 31, class: Int })) // SP (conceptual)
    insts.push(store_fp)

    // Store LR
    let store_lr = @instr.VCodeInst::new(Store(I64, lr_off))
    store_lr.add_use(Physical({ index: 30, class: Int })) // LR
    store_lr.add_use(Physical({ index: 31, class: Int })) // SP
    insts.push(store_lr)

    // Set up frame pointer: MOV x29, sp
    let setup_fp = @instr.VCodeInst::new(Move)
    setup_fp.add_def({ reg: Physical({ index: 29, class: Int }) })
    setup_fp.add_use(Physical({ index: 31, class: Int }))
    insts.push(setup_fp)
  }
  insts
}

///|
/// Generate epilogue instructions
pub fn AArch64StackFrame::gen_epilogue(
  self : AArch64StackFrame,
) -> Array[@instr.VCodeInst] {
  let insts : Array[@instr.VCodeInst] = []
  let frame_size = self.frame.size()
  if frame_size == 0 {
    return insts
  }

  // Restore FP and LR if using frame pointer
  if self.use_fp && (self.fp_slot, self.lr_slot) is (Some(fp_off), Some(lr_off)) {
    // Restore FP
    let load_fp = @instr.VCodeInst::new(Load(I64, fp_off))
    load_fp.add_def({ reg: Physical({ index: 29, class: Int }) })
    load_fp.add_use(Physical({ index: 31, class: Int })) // SP
    insts.push(load_fp)

    // Restore LR
    let load_lr = @instr.VCodeInst::new(Load(I64, lr_off))
    load_lr.add_def({ reg: Physical({ index: 30, class: Int }) })
    load_lr.add_use(Physical({ index: 31, class: Int })) // SP
    insts.push(load_lr)
  }

  // Restore stack pointer: ADD sp, sp, #frame_size (64-bit)
  let add_sp = @instr.VCodeInst::new(Add(true))
  add_sp.add_def({ reg: Physical({ index: 31, class: Int }) }) // SP
  add_sp.add_use(Physical({ index: 31, class: Int })) // SP
  insts.push(add_sp)
  insts
}

///|
fn AArch64StackFrame::print(self : AArch64StackFrame) -> String {
  let mut result = "AArch64 "
  result = result + self.frame.print()
  if self.use_fp {
    result = result + "Using frame pointer (x29)\n"
  }
  result
}

///|
pub impl Show for AArch64StackFrame with output(self, logger) {
  logger.write_string(self.print())
}

// ============ Stack Layout Builder ============

///|
/// Build stack layout from register allocation result
pub fn build_stack_layout_aarch64(
  alloc : RegAllocResult,
  func : VCodeFunction,
) -> AArch64StackFrame {
  let frame = AArch64StackFrame::new()

  // Setup FP/LR saves
  frame.setup()

  // Allocate spill slots for all spilled registers
  for entry in alloc.spill_slots {
    let (vreg_id, _slot_idx) = entry
    // Find the vreg info
    let vreg = find_vreg_by_id(func, vreg_id)
    if vreg is Some(v) {
      frame.alloc_spill(v) |> ignore
    }
  }

  // Finalize the frame
  frame.finalize()
  frame
}

///|
fn find_vreg_by_id(func : VCodeFunction, id : Int) -> @abi.VReg? {
  // Check params
  for param in func.params {
    if param.id == id {
      return Some(param)
    }
  }
  // Check instructions
  for block in func.blocks {
    for inst in block.insts {
      for def in inst.defs {
        if def.reg is Virtual(vreg) && vreg.id == id {
          return Some(vreg)
        }
      }
    }
  }
  None
}
