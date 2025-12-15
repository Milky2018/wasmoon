// JIT Stack Frame Layout
// Encapsulates stack frame layout computation for JIT-compiled functions
//
// This module provides a clean interface for managing:
// 1. Callee-saved register storage (GPRs and FPRs)
// 2. Spill slot allocation
// 3. Multi-value call result buffers
// 4. Stack pointer adjustment calculations

// ============ Constants ============

///|
const SPILL_SLOT_SIZE : Int = 8

///|
const SPILL_ALIGNMENT : Int = 16

///|
const MIN_SPILL_SIZE : Int = 16

///|
const CALL_RESULTS_BUFFER_SIZE : Int = 64

///|
const PAIR_SIZE : Int = 16

// ============ JITStackFrame ============

///|
/// Encapsulates the stack frame layout for a JIT-compiled function
pub struct JITStackFrame {
  // Size of each region (in bytes)
  gpr_save_size : Int
  fpr_save_size : Int
  spill_size : Int
  call_buffer_size : Int
  // Offset of each region from SP (after frame allocation)
  gpr_save_offset : Int
  fpr_save_offset : Int
  spill_offset : Int
  call_buffer_offset : Int
  // Total frame size (16-byte aligned)
  total_size : Int
  // Lists of saved registers
  saved_gprs : Array[Int]
  saved_fprs : Array[Int]
  // Flags
  needs_extra_results : Bool
  calls_multi_value : Bool
  uses_x23 : Bool
}

///|
/// Build a JITStackFrame from function metadata
pub fn JITStackFrame::build(
  clobbered_gprs : Array[Int],
  clobbered_fprs : Array[Int],
  num_spill_slots : Int,
  needs_extra_results~ : Bool,
  calls_multi_value~ : Bool,
) -> JITStackFrame {
  // Determine if we need X23 for extra results buffer
  let uses_x23 = needs_extra_results || calls_multi_value

  // Build the list of GPRs to save (base registers + clobbered)
  let saved_gprs = build_gpr_save_list(uses_x23, clobbered_gprs)

  // Calculate size of each region
  let gpr_save_size = calc_gpr_save_size(saved_gprs.length())
  let fpr_save_size = calc_fpr_save_size(clobbered_fprs.length())
  let spill_size = calc_spill_size(num_spill_slots)
  let call_buffer_size = if calls_multi_value && !needs_extra_results {
    CALL_RESULTS_BUFFER_SIZE
  } else {
    0
  }

  // Calculate offsets (regions are stacked from SP upward)
  // Layout: [GPR saves][FPR saves][spill slots][call buffer]
  let gpr_save_offset = 0
  let fpr_save_offset = gpr_save_offset + gpr_save_size
  let spill_offset = fpr_save_offset + fpr_save_size
  let call_buffer_offset = spill_offset + spill_size

  // Total size (must be 16-byte aligned)
  let unaligned_total = gpr_save_size +
    fpr_save_size +
    spill_size +
    call_buffer_size
  let total_size = align_up(unaligned_total, 16)
  {
    gpr_save_size,
    fpr_save_size,
    spill_size,
    call_buffer_size,
    gpr_save_offset,
    fpr_save_offset,
    spill_offset,
    call_buffer_offset,
    total_size,
    saved_gprs,
    saved_fprs: clobbered_fprs.copy(),
    needs_extra_results,
    calls_multi_value,
    uses_x23,
  }
}

///|
/// Get the stack offset for a spill slot index
pub fn JITStackFrame::get_spill_offset(
  self : JITStackFrame,
  slot_idx : Int,
) -> Int {
  self.spill_offset + slot_idx * SPILL_SLOT_SIZE
}

///|
/// Get the stack offset for the call results buffer
pub fn JITStackFrame::get_call_buffer_offset(self : JITStackFrame) -> Int {
  self.call_buffer_offset
}

// ============ Helper Functions ============

///|
/// Build the list of GPRs to save
/// Combines base registers (X19-X24) with clobbered registers
fn build_gpr_save_list(uses_x23 : Bool, clobbered : Array[Int]) -> Array[Int] {
  // Base registers that are always saved:
  // X19 (context), X20 (func_table), X21 (mem_base), X22 (mem_size), X24 (indirect_table)
  // Plus X23 if uses_x23 is true
  let base_regs : Array[Int] = if uses_x23 {
    [19, 20, 21, 22, 23, 24]
  } else {
    [19, 20, 21, 22, 24]
  }

  // Combine base registers with clobbered registers (avoiding duplicates)
  let result : Array[Int] = []
  for reg in base_regs {
    result.push(reg)
  }
  for reg in clobbered {
    if !result.contains(reg) {
      result.push(reg)
    }
  }
  result.sort()
  result
}

///|
/// Calculate GPR save area size (pairs are 16 bytes each)
fn calc_gpr_save_size(num_gprs : Int) -> Int {
  let num_pairs = (num_gprs + 1) / 2
  num_pairs * PAIR_SIZE
}

///|
/// Calculate FPR save area size (pairs are 16 bytes each)
fn calc_fpr_save_size(num_fprs : Int) -> Int {
  let num_pairs = (num_fprs + 1) / 2
  num_pairs * PAIR_SIZE
}

///|
/// Calculate spill slot area size (minimum 16 bytes for scratch space)
fn calc_spill_size(num_slots : Int) -> Int {
  let raw_size = num_slots * SPILL_SLOT_SIZE
  let aligned_size = align_up(raw_size, SPILL_ALIGNMENT)
  if aligned_size < MIN_SPILL_SIZE {
    MIN_SPILL_SIZE
  } else {
    aligned_size
  }
}

///|
/// Align value up to the given alignment
fn align_up(value : Int, alignment : Int) -> Int {
  (value + alignment - 1) / alignment * alignment
}
