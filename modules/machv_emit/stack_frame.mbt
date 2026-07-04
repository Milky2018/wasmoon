///|
const SPILL_SLOT_SIZE : Int = 8

///|
const SPILL_ALIGNMENT : Int = 16

///|
const MIN_SPILL_SIZE : Int = 16

///|
pub(all) struct StackFrameLayout {
  setup_area_size : Int
  gpr_save_size : Int
  fpr_save_size : Int
  spill_size : Int
  outgoing_args_size : Int
  gpr_save_offset : Int
  fpr_save_offset : Int
  spill_offset : Int
  outgoing_args_offset : Int
  total_size : Int
  frame_size : Int
  saved_gprs : Array[Int]
  saved_fprs : Array[Int]
  has_setup_area : Bool
} derive(Eq, Debug)

///|
pub fn StackFrameLayout::build(
  saved_gprs : Array[Int],
  saved_fprs : Array[Int],
  num_spill_slots : Int,
  has_setup_area : Bool,
  setup_area_size : Int,
  outgoing_args_size? : Int = 0,
) -> StackFrameLayout {
  let effective_setup_area_size = if has_setup_area {
    setup_area_size
  } else {
    0
  }
  let gpr_save_size = calc_pair_save_size(saved_gprs.length())
  let fpr_save_size = calc_pair_save_size(saved_fprs.length())
  let spill_size = calc_spill_size(num_spill_slots)
  let aligned_outgoing = align_up(outgoing_args_size, 16)
  let frame_size = gpr_save_size + fpr_save_size + spill_size + aligned_outgoing
  let outgoing_args_offset = 0
  let spill_offset = aligned_outgoing
  let fpr_save_offset = spill_offset + spill_size
  let gpr_save_offset = fpr_save_offset + fpr_save_size
  let total_size = effective_setup_area_size + frame_size
  {
    setup_area_size: effective_setup_area_size,
    gpr_save_size,
    fpr_save_size,
    spill_size,
    outgoing_args_size: aligned_outgoing,
    gpr_save_offset,
    fpr_save_offset,
    spill_offset,
    outgoing_args_offset,
    total_size,
    frame_size,
    saved_gprs: saved_gprs.copy(),
    saved_fprs: saved_fprs.copy(),
    has_setup_area,
  }
}

///|
pub fn StackFrameLayout::get_spill_offset(
  self : StackFrameLayout,
  slot_idx : Int,
) -> Int {
  self.spill_offset + slot_idx * SPILL_SLOT_SIZE
}

///|
pub fn StackFrameLayout::get_outgoing_arg_offset(
  self : StackFrameLayout,
  arg_offset : Int,
) -> Int {
  self.outgoing_args_offset + arg_offset
}

///|
pub fn StackFrameLayout::get_gpr_save_offset(
  self : StackFrameLayout,
  reg_idx : Int,
) -> Int {
  for i, reg in self.saved_gprs {
    if reg == reg_idx {
      return self.gpr_save_offset + i * 8
    }
  }
  -1
}

///|
pub fn StackFrameLayout::get_fpr_save_offset(
  self : StackFrameLayout,
  reg_idx : Int,
) -> Int {
  for i, reg in self.saved_fprs {
    if reg == reg_idx {
      return self.fpr_save_offset + i * 8
    }
  }
  -1
}

///|
fn calc_pair_save_size(num_regs : Int) -> Int {
  if num_regs == 0 {
    return 0
  }
  align_up(num_regs * 8, 16)
}

///|
fn calc_spill_size(num_slots : Int) -> Int {
  if num_slots == 0 {
    return 0
  }
  let raw_size = num_slots * SPILL_SLOT_SIZE
  let aligned_size = align_up(raw_size, SPILL_ALIGNMENT)
  if aligned_size < MIN_SPILL_SIZE {
    MIN_SPILL_SIZE
  } else {
    aligned_size
  }
}

///|
fn align_up(value : Int, alignment : Int) -> Int {
  (value + alignment - 1) / alignment * alignment
}
