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
/// Size of setup area (FP + LR)
const SETUP_AREA_SIZE : Int = 16

///|
// amd64 has no link register; reserve 8 bytes when frame setup is needed
// (push rbp) so that, starting from a SysV entry SP of 16n+8, the stack is
// 16-byte aligned (16n) after the prologue and therefore aligned at call sites.
const X86_SETUP_AREA_SIZE : Int = 8

// ============ JITStackFrame ============

///|
/// Encapsulates the stack frame layout for a JIT-compiled function
pub struct JITStackFrame {
  // Size of each region (in bytes)
  setup_area_size : Int // ISA-dependent setup (AArch64: FP+LR=16, amd64: push rbp=8)
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
  // Total frame size:
  // - AArch64: 16-byte aligned (SP must remain aligned at all times)
  // - amd64: chosen so SP is 16-byte aligned after the prologue (SysV call ABI)
  total_size : Int
  // Size of frame excluding setup area (for sub sp, sp, #size)
  frame_size : Int
  // Lists of saved registers
  saved_gprs : Array[Int] // Callee-saved GPRs to save (excluding FP/LR)
  saved_fprs : Array[Int] // Callee-saved FPRs to save
  // Flags
  has_setup_area : Bool // Whether FP/LR are saved
  needs_vmctx : Bool // Whether function uses vmctx (X19)
  cache_mem0_desc : Bool // Whether to cache memory0 base in X20
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
  isa? : @isa.ISA = @isa.ISA::current(),
  abi_settings? : @abi.ABISettings = @abi.ABISettings::default(),
) -> JITStackFrame {
  let isa = isa
  let abi_settings = abi_settings
  // Build the list of GPRs to save
  // ABI: saved GPR set + clobbered callee-saved regs
  let saved_gprs = build_gpr_save_list_v3(clobbered_gprs, isa, abi_settings)

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

  // Calculate generic frame regions in `machv_emit`; this package only owns
  // ABI-specific save-list selection and setup-area size.
  let setup_area_size = if has_setup_area {
    match isa {
      AArch64 => SETUP_AREA_SIZE
      AMD64 => X86_SETUP_AREA_SIZE
    }
  } else {
    0
  }
  let layout = @machv_emit.StackFrameLayout::build(
    saved_gprs,
    clobbered_fprs,
    num_spill_slots,
    has_setup_area,
    setup_area_size,
    outgoing_args_size~,
  )
  {
    setup_area_size: layout.setup_area_size,
    gpr_save_size: layout.gpr_save_size,
    fpr_save_size: layout.fpr_save_size,
    spill_size: layout.spill_size,
    outgoing_args_size: layout.outgoing_args_size,
    gpr_save_offset: layout.gpr_save_offset,
    fpr_save_offset: layout.fpr_save_offset,
    spill_offset: layout.spill_offset,
    outgoing_args_offset: layout.outgoing_args_offset,
    total_size: layout.total_size,
    frame_size: layout.frame_size,
    saved_gprs: layout.saved_gprs,
    saved_fprs: layout.saved_fprs,
    has_setup_area: layout.has_setup_area,
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
  let layout = self.to_layout()
  layout.get_spill_offset(slot_idx)
}

///|
/// Get the stack offset for outgoing arguments
pub fn JITStackFrame::get_outgoing_arg_offset(
  self : JITStackFrame,
  arg_offset : Int,
) -> Int {
  let layout = self.to_layout()
  layout.get_outgoing_arg_offset(arg_offset)
}

///|
/// Get the offset for saving a specific GPR (relative to SP after frame setup)
pub fn JITStackFrame::get_gpr_save_offset(
  self : JITStackFrame,
  reg_idx : Int,
) -> Int {
  let layout = self.to_layout()
  layout.get_gpr_save_offset(reg_idx)
}

///|
/// Get the offset for saving a specific FPR (relative to SP after frame setup)
pub fn JITStackFrame::get_fpr_save_offset(
  self : JITStackFrame,
  reg_idx : Int,
) -> Int {
  let layout = self.to_layout()
  layout.get_fpr_save_offset(reg_idx)
}

///|
fn JITStackFrame::to_layout(
  self : JITStackFrame,
) -> @machv_emit.StackFrameLayout {
  {
    setup_area_size: self.setup_area_size,
    gpr_save_size: self.gpr_save_size,
    fpr_save_size: self.fpr_save_size,
    spill_size: self.spill_size,
    outgoing_args_size: self.outgoing_args_size,
    gpr_save_offset: self.gpr_save_offset,
    fpr_save_offset: self.fpr_save_offset,
    spill_offset: self.spill_offset,
    outgoing_args_offset: self.outgoing_args_offset,
    total_size: self.total_size,
    frame_size: self.frame_size,
    saved_gprs: self.saved_gprs,
    saved_fprs: self.saved_fprs,
    spill_slot_offsets: [],
    has_setup_area: self.has_setup_area,
  }
}

// ============ Helper Functions ============

///|
/// Build the list of callee-saved GPRs to save.
///
/// Cranelift behavior: when `enable_pinned_reg` is enabled, the pinned VMContext
/// register is globally-reserved and is not saved/restored in prologues.
fn build_gpr_save_list_v3(
  clobbered : Array[Int],
  isa : @isa.ISA,
  abi_settings : @abi.ABISettings,
) -> Array[Int] {
  let fp = isa.fp_reg_index()
  let lr = isa.lr_reg_index()
  let env = isa.machine_env(settings=abi_settings)
  let callee : @hashset.HashSet[Int] = HashSet([])
  for r in env.callee_saved_int {
    callee.add(r.index)
  }
  let result : Array[Int] = []
  for reg in clobbered {
    // FP/LR are handled separately in the setup area.
    if reg == fp || reg == lr {
      continue
    }
    if callee.contains(reg) && !result.contains(reg) {
      result.push(reg)
    }
  }
  result.sort()
  result
}
