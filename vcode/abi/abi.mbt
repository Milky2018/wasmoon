// ABI Constants and Definitions
// Centralized definition of JIT calling convention
//
// Wasmoon JIT ABI (transitioning to Cranelift AppleAarch64):
// - X0: vmctx (VMContext)
// - X1-X7: user integer parameters (up to 7 in registers)
// - V0-V7: float parameters (S for f32, D for f64)
// - X21: pinned vmctx register (cached in prologue)
// - X29: Frame Pointer (FP)
// - X30: Link Register (LR)

// ============ VMContext Structure Offsets ============
// These must match the C struct layout in jit_ffi.h
// VMContext layout (see jit_ffi.h):
//   +0:  memory0 (wasmoon_memory_t*)  - memory 0 definition pointer
//   +8:  func_table (void**)          - function pointer array
//   +16: table0_base (void**)         - table 0 base (fast path for call_indirect)
//   +24: table0_elements (size_t)     - table 0 element count
//   +32: globals (void*)              - global variable array
//   +40: tables (void***)             - multi-table pointer array
//   +48: table_count (int)
//   +56: table_sizes (size_t*)
//   +64: table_max_sizes (size_t*)
//   +72: memories (wasmoon_memory_t**)
//   +80: memory_count (int)
//   +84: debug_current_func_idx (int32)
//   +88: gc_heap_ptr (uint8_t*)
//   +96: gc_heap_limit (uint8_t*)
//   +104: gc_heap (void*)

///|
/// Offset of memory0 (wasmoon_memory_t*)
pub const VMCTX_MEMORY0_OFFSET : Int = 0

///|
/// Offset of func_table
pub const VMCTX_FUNC_TABLE_OFFSET : Int = 8

///|
/// Offset of table0_base
pub const VMCTX_TABLE0_BASE_OFFSET : Int = 16

///|
/// Offset of table0_elements
pub const VMCTX_TABLE0_ELEMENTS_OFFSET : Int = 24

///|
/// Offset of globals
pub const VMCTX_GLOBALS_OFFSET : Int = 32

///|
/// Offset of tables array
pub const VMCTX_TABLES_OFFSET : Int = 40

///|
/// Offset of table_count
pub const VMCTX_TABLE_COUNT_OFFSET : Int = 48

///|
/// Offset of table_sizes
pub const VMCTX_TABLE_SIZES_OFFSET : Int = 56

///|
/// Offset of table_max_sizes
pub const VMCTX_TABLE_MAX_SIZES_OFFSET : Int = 64

///|
/// Offset of memories array
pub const VMCTX_MEMORIES_OFFSET : Int = 72

///|
/// Offset of memory_count
pub const VMCTX_MEMORY_COUNT_OFFSET : Int = 80

///|
/// Offset of debug_current_func_idx
pub const VMCTX_DEBUG_CURRENT_FUNC_IDX_OFFSET : Int = 84

///|
/// Offset of gc_heap_ptr
pub const VMCTX_GC_HEAP_PTR_OFFSET : Int = 88

///|
/// Offset of gc_heap_limit
pub const VMCTX_GC_HEAP_LIMIT_OFFSET : Int = 96

///|
/// Offset of gc_heap
pub const VMCTX_GC_HEAP_OFFSET : Int = 104

// ============ Reserved Registers ============

///|
/// Register holding cached VMContext (Cranelift pinned-reg: X21).
/// In prologue (pinned mode): mov x21, x0
pub const REG_VMCTX : Int = 21

///|
/// Register holding cached memory0 descriptor pointer (X20, callee-saved).
/// When enabled, prologue loads: x20 = [x19 + VMCTX_MEMORY0_OFFSET].
pub const REG_MEM0_DESC : Int = 20

///|
/// Register holding cached func_table pointer (X19, callee-saved).
/// When enabled, prologue loads: x19 = [vmctx + VMCTX_FUNC_TABLE_OFFSET].
pub const REG_FUNC_TABLE : Int = 19

///|
/// Frame Pointer register (X29)
pub const REG_FP : Int = 29

///|
/// Link Register (X30)
pub const REG_LR : Int = 30

// ============ Parameter Passing ============

///|
/// Register for VMContext (first parameter, X0)
pub const REG_CALLEE_VMCTX : Int = 0

///|
/// First register for user integer parameters (X1)
pub const USER_PARAM_BASE_REG : Int = 1

///|
/// Maximum number of user integer parameters in registers (X1-X7 = 7)
pub const MAX_USER_REG_PARAMS : Int = 7

///|
/// First register for float parameters (V0/D0/S0)
pub const FLOAT_PARAM_BASE_REG : Int = 0

///|
/// Maximum number of float parameters in registers (V0-V7 = 8)
pub const MAX_FLOAT_REG_PARAMS : Int = 8

///|
/// First register for integer parameters (X0)
pub const PARAM_BASE_REG : Int = 0

///|
/// Maximum number of integer parameters in registers (X0-X7 = 8)
pub const MAX_REG_PARAMS : Int = 8

// ============ Return Value Registers ============

///|
/// Maximum number of integer return values in registers (X0-X7 = 8)
pub const MAX_INT_RET_REGS : Int = 8

///|
/// Maximum number of float return values in registers (V0-V7 = 8)
pub const MAX_FLOAT_RET_REGS : Int = 8

///|
/// Register for SRET pointer when return values exceed register capacity
pub const REG_SRET : Int = 8

// ============ Scratch Registers ============

///|
/// Primary scratch register for code emission (X16/IP0)
pub const SCRATCH_REG_1 : Int = 16

///|
/// Secondary scratch register (X17/IP1)
pub const SCRATCH_REG_2 : Int = 17

// ============ ABI Helpers ============

///|
/// Align value up to the next multiple of `align` (which must be a power of two).
pub fn align_up(value : Int, align : Int) -> Int {
  if align <= 1 {
    value
  } else {
    (value + (align - 1)) / align * align
  }
}

///|
/// Stack slot size (bytes) for the Wasm v3 calling convention overflow area.
/// We keep 8-byte slots for scalars for simplicity; V128 occupies 16 bytes.
pub fn wasm_stack_slot_size(class : RegClass) -> Int {
  match class {
    Vector => 16
    _ => 8
  }
}

///|
/// Stack slot alignment (bytes) for the Wasm v3 calling convention overflow area.
pub fn wasm_stack_slot_align(class : RegClass) -> Int {
  match class {
    Vector => 16
    _ => 8
  }
}

///|
/// Compute overflow argument stack layout for the Wasm v3 calling convention.
/// Layout: [int_overflow...][float_overflow...] with V128 aligned to 16.
///
/// Returned offsets are relative to the start of the overflow area.
/// The total size is 16-byte aligned for stack frame allocation.
pub fn wasm_layout_overflow_stack(
  int_overflow_count : Int,
  float_overflow_classes : Array[RegClass],
) -> (Array[Int], Array[Int], Int) {
  let int_offsets : Array[Int] = []
  for i in 0..<int_overflow_count {
    int_offsets.push(i * 8)
  }
  let float_offsets : Array[Int] = []
  let mut cur = int_overflow_count * 8
  for class in float_overflow_classes {
    cur = align_up(cur, wasm_stack_slot_align(class))
    float_offsets.push(cur)
    cur = cur + wasm_stack_slot_size(class)
  }
  let total = align_up(cur, 16)
  (int_offsets, float_offsets, total)
}

// ============ Register Usage in AAPCS64 ============

///|
/// AAPCS64 parameter registers (arguments)
/// X0-X7 for integer/pointer arguments
pub fn aapcs64_arg_gprs() -> Array[PReg] {
  [
    { index: 0, class: Int },
    { index: 1, class: Int },
    { index: 2, class: Int },
    { index: 3, class: Int },
    { index: 4, class: Int },
    { index: 5, class: Int },
    { index: 6, class: Int },
    { index: 7, class: Int },
  ]
}

///|
/// AAPCS64 integer return registers
/// X0-X7 can be used for return values (up to 8)
pub fn aapcs64_ret_gprs() -> Array[PReg] {
  [
    { index: 0, class: Int },
    { index: 1, class: Int },
    { index: 2, class: Int },
    { index: 3, class: Int },
    { index: 4, class: Int },
    { index: 5, class: Int },
    { index: 6, class: Int },
    { index: 7, class: Int },
  ]
}

///|
/// AAPCS64 callee-saved registers
pub fn aapcs64_callee_saved() -> Array[PReg] {
  [
    { index: 19, class: Int },
    { index: 20, class: Int },
    { index: 21, class: Int },
    { index: 22, class: Int },
    { index: 23, class: Int },
    { index: 24, class: Int },
    { index: 25, class: Int },
    { index: 26, class: Int },
    { index: 27, class: Int },
    { index: 28, class: Int },
    { index: 29, class: Int }, // FP
    { index: 30, class: Int }, // LR
  ]
}

///|
/// Scratch registers available for allocation (caller-saved, no save/restore needed)
/// X0-X15 are available for allocation.
/// X16-X17 (IP0/IP1) are reserved for linker/code emission scratch and indirect calls.
pub fn allocatable_scratch_regs() -> Array[PReg] {
  [
    { index: 0, class: Int },
    { index: 1, class: Int },
    { index: 2, class: Int },
    { index: 3, class: Int },
    { index: 4, class: Int },
    { index: 5, class: Int },
    { index: 6, class: Int },
    { index: 7, class: Int },
    { index: 8, class: Int },
    { index: 9, class: Int },
    { index: 10, class: Int },
    { index: 11, class: Int },
    { index: 12, class: Int },
    { index: 13, class: Int },
    { index: 14, class: Int },
    { index: 15, class: Int },
  ]
}

///|
/// Callee-saved registers available for allocation (must be saved/restored).
///
/// When `enable_pinned_reg` is true (Cranelift-style pinned VMContext), X21 is
/// reserved and excluded from allocation.
///
/// When `enable_pinned_reg` is false, X21 becomes allocatable (unpinned mode).
pub fn allocatable_callee_saved_regs(
  enable_pinned_reg? : Bool = true,
) -> Array[PReg] {
  if enable_pinned_reg {
    [
      { index: 19, class: Int },
      { index: 20, class: Int },
      { index: 22, class: Int },
      { index: 23, class: Int },
      { index: 24, class: Int },
      { index: 25, class: Int },
      { index: 26, class: Int },
      { index: 27, class: Int },
      { index: 28, class: Int },
    ]
  } else {
    [
      { index: 19, class: Int },
      { index: 20, class: Int },
      { index: 21, class: Int },
      { index: 22, class: Int },
      { index: 23, class: Int },
      { index: 24, class: Int },
      { index: 25, class: Int },
      { index: 26, class: Int },
      { index: 27, class: Int },
      { index: 28, class: Int },
    ]
  }
}

///|
/// AAPCS64 floating-point argument registers
/// V0-V7 (using D for f64, S for f32)
pub fn aapcs64_arg_fprs() -> Array[PReg] {
  [
    { index: 0, class: Float64 },
    { index: 1, class: Float64 },
    { index: 2, class: Float64 },
    { index: 3, class: Float64 },
    { index: 4, class: Float64 },
    { index: 5, class: Float64 },
    { index: 6, class: Float64 },
    { index: 7, class: Float64 },
  ]
}

///|
/// AAPCS64 floating-point return registers
/// V0-V7 can be used for return values (up to 8)
pub fn aapcs64_ret_fprs() -> Array[PReg] {
  [
    { index: 0, class: Float64 },
    { index: 1, class: Float64 },
    { index: 2, class: Float64 },
    { index: 3, class: Float64 },
    { index: 4, class: Float64 },
    { index: 5, class: Float64 },
    { index: 6, class: Float64 },
    { index: 7, class: Float64 },
  ]
}

///|
/// Registers clobbered by function calls (caller-saved)
/// These are registers that the caller must assume are destroyed after a call.
/// X0-X17 for integer (args, return, scratch)
pub fn call_clobbered_gprs() -> Array[PReg] {
  [
    { index: 0, class: Int },
    { index: 1, class: Int },
    { index: 2, class: Int },
    { index: 3, class: Int },
    { index: 4, class: Int },
    { index: 5, class: Int },
    { index: 6, class: Int },
    { index: 7, class: Int },
    { index: 8, class: Int },
    { index: 9, class: Int },
    { index: 10, class: Int },
    { index: 11, class: Int },
    { index: 12, class: Int },
    { index: 13, class: Int },
    { index: 14, class: Int },
    { index: 15, class: Int },
    { index: 16, class: Int },
    { index: 17, class: Int },
  ]
}

///|

///|
/// Floating-point registers clobbered by function calls.
///
/// Cranelift conservatively treats all V0-V31 as clobbered at callsites because
/// it cannot model partial preservation of V8-V15.
///
/// For AppleAarch64 parity, we follow the same conservative approximation.
pub fn call_clobbered_fprs() -> Array[PReg] {
  [
    { index: 0, class: Float64 },
    { index: 1, class: Float64 },
    { index: 2, class: Float64 },
    { index: 3, class: Float64 },
    { index: 4, class: Float64 },
    { index: 5, class: Float64 },
    { index: 6, class: Float64 },
    { index: 7, class: Float64 },
    { index: 8, class: Float64 },
    { index: 9, class: Float64 },
    { index: 10, class: Float64 },
    { index: 11, class: Float64 },
    { index: 12, class: Float64 },
    { index: 13, class: Float64 },
    { index: 14, class: Float64 },
    { index: 15, class: Float64 },
    { index: 16, class: Float64 },
    { index: 17, class: Float64 },
    { index: 18, class: Float64 },
    { index: 19, class: Float64 },
    { index: 20, class: Float64 },
    { index: 21, class: Float64 },
    { index: 22, class: Float64 },
    { index: 23, class: Float64 },
    { index: 24, class: Float64 },
    { index: 25, class: Float64 },
    { index: 26, class: Float64 },
    { index: 27, class: Float64 },
    { index: 28, class: Float64 },
    { index: 29, class: Float64 },
    { index: 30, class: Float64 },
    { index: 31, class: Float64 },
  ]
}

///|
/// Floating-point registers clobbered by *same-ABI* calls.
///
/// When both caller and callee use the same AArch64 ABI, V8-V15 are callee-saved
/// (low 64 bits). We treat them as preserved across Wasm-to-Wasm calls.
///
/// This mirrors Cranelift’s practice of excluding V8-V15 clobbers when the callee
/// has the same ABI as the caller.
pub fn call_clobbered_fprs_same_abi() -> Array[PReg] {
  [
    { index: 0, class: Float64 },
    { index: 1, class: Float64 },
    { index: 2, class: Float64 },
    { index: 3, class: Float64 },
    { index: 4, class: Float64 },
    { index: 5, class: Float64 },
    { index: 6, class: Float64 },
    { index: 7, class: Float64 },
    { index: 16, class: Float64 },
    { index: 17, class: Float64 },
    { index: 18, class: Float64 },
    { index: 19, class: Float64 },
    { index: 20, class: Float64 },
    { index: 21, class: Float64 },
    { index: 22, class: Float64 },
    { index: 23, class: Float64 },
    { index: 24, class: Float64 },
    { index: 25, class: Float64 },
    { index: 26, class: Float64 },
    { index: 27, class: Float64 },
    { index: 28, class: Float64 },
    { index: 29, class: Float64 },
    { index: 30, class: Float64 },
    { index: 31, class: Float64 },
  ]
}

///|
/// Callee-saved floating-point registers (V8-V15 low 64 bits in AAPCS64)
/// Functions must preserve these across calls
pub fn callee_saved_fprs() -> Array[PReg] {
  [
    { index: 8, class: Float64 },
    { index: 9, class: Float64 },
    { index: 10, class: Float64 },
    { index: 11, class: Float64 },
    { index: 12, class: Float64 },
    { index: 13, class: Float64 },
    { index: 14, class: Float64 },
    { index: 15, class: Float64 },
  ]
}

///|
/// Allocatable floating-point registers (caller-saved, no save/restore needed)
/// V16-V31 are all available for allocation.
pub fn allocatable_scratch_fprs() -> Array[PReg] {
  [
    { index: 16, class: Float64 },
    { index: 17, class: Float64 },
    { index: 18, class: Float64 },
    { index: 19, class: Float64 },
    { index: 20, class: Float64 },
    { index: 21, class: Float64 },
    { index: 22, class: Float64 },
    { index: 23, class: Float64 },
    { index: 24, class: Float64 },
    { index: 25, class: Float64 },
    { index: 26, class: Float64 },
    { index: 27, class: Float64 },
    { index: 28, class: Float64 },
    { index: 29, class: Float64 },
    { index: 30, class: Float64 },
    { index: 31, class: Float64 },
  ]
}

///|
/// Allocatable callee-saved floating-point registers (must be saved/restored)
/// V8-V15 are callee-saved (low 64 bits)
pub fn allocatable_callee_saved_fprs() -> Array[PReg] {
  [
    { index: 8, class: Float64 },
    { index: 9, class: Float64 },
    { index: 10, class: Float64 },
    { index: 11, class: Float64 },
    { index: 12, class: Float64 },
    { index: 13, class: Float64 },
    { index: 14, class: Float64 },
    { index: 15, class: Float64 },
  ]
}
