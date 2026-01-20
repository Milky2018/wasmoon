// JIT Stack Frame Layout (Standard style)
// Encapsulates stack frame layout computation for JIT-compiled functions
//
// Standard Stack Frame Layout (from high to low address):
// ┌───────────────────────────┐
// │  Caller's Stack Args      │ (if any)
// ├═══════════════════════════┤ ← SP at function entry
// │  Frame Pointer (X29)      │ ← Pushed first with STP pre-indexed
// ├───────────────────────────┤
// │  Link Register (X30)      │
// ├───────────────────────────┤ ← FP points here
// │  Clobbered GPRs (X19-X28) │ ← Pushed second
// ├───────────────────────────┤
// │  Clobbered FPRs (V8-V15)  │ ← Pushed third
// ├───────────────────────────┤
// │  Spill Slots              │ ← Allocated via SUB SP
// ├───────────────────────────┤
// │  Outgoing Arguments       │ ← Allocated via SUB SP
// └═══════════════════════════┘ ← SP after prologue
//
// Key difference from old layout: FP/LR is at the TOP (highest address),
// not at SP+0. This approach using fixed-size pre-indexed
// pushes that avoid SImm7 overflow issues with large frames.

// ============ Constants ============

///|
const SPILL_SLOT_SIZE : Int = 8

///|
const SPILL_ALIGNMENT : Int = 16

///|
const MIN_SPILL_SIZE : Int = 16

///|
const PAIR_SIZE : Int = 16

///|
/// Size of setup area (FP + LR)
const SETUP_AREA_SIZE : Int = 16

// ============ JITStackFrame ============

///|
/// Encapsulates the stack frame layout for a JIT-compiled function
pub struct JITStackFrame {
  // Size of each region (in bytes)
  setup_area_size : Int // FP + LR (16 bytes if present)
  gpr_save_size : Int // Callee-saved GPRs (excluding FP/LR)
  fpr_save_size : Int // Callee-saved FPRs
  spill_size : Int // Spill slots
  outgoing_args_size : Int // Stack space for call arguments
  // Offset of each region from SP (after frame allocation)
  // These are positive offsets from SP pointing upward
  gpr_save_offset : Int
  fpr_save_offset : Int
  spill_offset : Int
  outgoing_args_offset : Int
  // Total frame size (16-byte aligned, including setup area)
  total_size : Int
  // Size of frame excluding setup area (for sub sp, sp, #size)
  frame_size : Int
  // Lists of saved registers
  saved_gprs : Array[Int] // Callee-saved GPRs to save (excluding FP/LR)
  saved_fprs : Array[Int] // Callee-saved FPRs to save
  // Flags
  has_setup_area : Bool // Whether FP/LR are saved
  needs_vmctx : Bool // Whether function uses vmctx (X19)
  cache_mem0_desc : Bool // Whether to cache memory0 descriptor in X20
  cache_func_table : Bool // Whether to cache func_table pointer in X21
}

///|
/// Build a JITStackFrame from function metadata
///
/// Parameters:
/// - clobbered_gprs: GPRs that are clobbered and need saving (callee-saved only)
/// - clobbered_fprs: FPRs that are clobbered and need saving (callee-saved only)
/// - num_spill_slots: Number of spill slots needed
/// - has_calls: Whether function contains calls (requires FP/LR save)
/// - outgoing_args_size: Stack space needed for outgoing call arguments
/// - needs_vmctx: Whether function uses vmctx (pinned reg)
/// - has_incoming_stack_args: Whether function reads any stack parameters
pub fn JITStackFrame::build(
  clobbered_gprs : Array[Int],
  clobbered_fprs : Array[Int],
  num_spill_slots : Int,
  has_calls? : Bool = false,
  outgoing_args_size? : Int = 0,
  needs_vmctx? : Bool = true,
  cache_mem0_desc? : Bool = false,
  cache_func_table? : Bool = false,
  force_frame_setup? : Bool = false,
  has_incoming_stack_args? : Bool = false,
) -> JITStackFrame {
  // Build the list of GPRs to save
  // ABI: saved GPR set + clobbered callee-saved regs
  let saved_gprs = build_gpr_save_list_v3(clobbered_gprs, needs_vmctx)

  // Determine if we need setup area (FP/LR)
  // Required when:
  // - Function makes calls (need to save LR)
  // - Function has callee-saved registers to save
  // - Function has spill slots (need frame reference)
  // - force_frame_setup is true (for DWARF/backtrace support)
  let has_setup_area = force_frame_setup ||
    has_calls ||
    has_incoming_stack_args ||
    saved_gprs.length() > 0 ||
    clobbered_fprs.length() > 0 ||
    num_spill_slots > 0

  // Calculate size of each region
  let setup_area_size = if has_setup_area { SETUP_AREA_SIZE } else { 0 }
  let gpr_save_size = calc_gpr_save_size(saved_gprs.length())
  let fpr_save_size = calc_fpr_save_size(clobbered_fprs.length())
  let spill_size = calc_spill_size(num_spill_slots)
  let aligned_outgoing = align_up(outgoing_args_size, 16)

  // Calculate frame size (excluding setup area, which is handled separately)
  // Standard layout from SP upward:
  // [SP+0]: outgoing args
  // [SP+outgoing]: spill slots
  // [SP+outgoing+spill]: FPR saves
  // [SP+outgoing+spill+fpr]: GPR saves
  // [SP+total-16]: FP/LR (at the top)
  let frame_size = gpr_save_size + fpr_save_size + spill_size + aligned_outgoing

  // Calculate offsets (from SP after frame allocation)
  // Standard style: outgoing args at bottom, FP/LR at top
  let outgoing_args_offset = 0
  let spill_offset = aligned_outgoing
  let fpr_save_offset = spill_offset + spill_size
  let gpr_save_offset = fpr_save_offset + fpr_save_size

  // Total size includes setup area
  let total_size = setup_area_size + frame_size
  {
    setup_area_size,
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
    saved_gprs,
    saved_fprs: clobbered_fprs.copy(),
    has_setup_area,
    needs_vmctx,
    cache_mem0_desc,
    cache_func_table,
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
/// Get the stack offset for outgoing arguments
pub fn JITStackFrame::get_outgoing_arg_offset(
  self : JITStackFrame,
  arg_offset : Int,
) -> Int {
  self.outgoing_args_offset + arg_offset
}

///|
/// Get the offset for saving a specific GPR (relative to SP after frame setup)
pub fn JITStackFrame::get_gpr_save_offset(
  self : JITStackFrame,
  reg_idx : Int,
) -> Int {
  // Find the register in the saved list
  for i, reg in self.saved_gprs {
    if reg == reg_idx {
      // Registers are saved in pairs at gpr_save_offset
      // First pair at gpr_save_offset, second at gpr_save_offset + 16, etc.
      let pair_idx = i / 2
      let in_pair_offset = i % 2 * 8
      return self.gpr_save_offset + pair_idx * PAIR_SIZE + in_pair_offset
    }
  }
  // Register not found, should not happen
  -1
}

///|
/// Get the offset for saving a specific FPR (relative to SP after frame setup)
pub fn JITStackFrame::get_fpr_save_offset(
  self : JITStackFrame,
  reg_idx : Int,
) -> Int {
  for i, reg in self.saved_fprs {
    if reg == reg_idx {
      let pair_idx = i / 2
      let in_pair_offset = i % 2 * 8
      return self.fpr_save_offset + pair_idx * PAIR_SIZE + in_pair_offset
    }
  }
  -1
}

// ============ Helper Functions ============

///|
/// Build the list of callee-saved GPRs to save.
///
/// Cranelift behavior: when `enable_pinned_reg` is enabled, the pinned VMContext
/// register is globally-reserved and is not saved/restored in prologues.
fn build_gpr_save_list_v3(
  clobbered : Array[Int],
  needs_vmctx : Bool,
) -> Array[Int] {
  needs_vmctx |> ignore
  let result : Array[Int] = []

  // Add clobbered callee-saved registers (X19-X28), excluding the pinned VMCTX.
  for reg in clobbered {
    // X29/X30 handled separately in setup area.
    if reg >= 19 && reg <= 28 && reg != @abi.REG_VMCTX && !result.contains(reg) {
      result.push(reg)
    }
  }
  result.sort()
  result
}

///|
/// Calculate GPR save area size (pairs are 16 bytes each)
fn calc_gpr_save_size(num_gprs : Int) -> Int {
  if num_gprs == 0 {
    return 0
  }
  let num_pairs = (num_gprs + 1) / 2
  num_pairs * PAIR_SIZE
}

///|
/// Calculate FPR save area size (pairs are 16 bytes each)
fn calc_fpr_save_size(num_fprs : Int) -> Int {
  if num_fprs == 0 {
    return 0
  }
  let num_pairs = (num_fprs + 1) / 2
  num_pairs * PAIR_SIZE
}

///|
/// Calculate spill slot area size
/// Returns 0 for leaf functions with no spills (no unnecessary stack allocation)
fn calc_spill_size(num_slots : Int) -> Int {
  if num_slots == 0 {
    return 0 // Leaf functions without spills need no stack space
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
/// Align value up to the given alignment
fn align_up(value : Int, alignment : Int) -> Int {
  (value + alignment - 1) / alignment * alignment
}
