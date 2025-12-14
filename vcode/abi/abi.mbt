// ABI Constants and Definitions
// Centralized definition of JIT calling convention
//
// New JIT ABI (v2):
// - X0-X7: User parameters (AAPCS64 compatible)
// - D0-D7: Float parameters (AAPCS64 compatible)
// - X20: Context pointer (callee-saved, shared across calls)
// - X21: Memory base (cached from context)
// - X22: Memory size (cached from context)
// - X23: Extra results buffer pointer (optional)
// - X24: Indirect table pointer (cached from context)

// ============ JITContext Structure Offsets ============
// These must match the C struct layout in ffi_jit.c

///|
/// Offset of func_table in JITContext
pub const CTX_FUNC_TABLE_OFFSET : Int = 0

///|
/// Offset of indirect_table in JITContext
pub const CTX_INDIRECT_TABLE_OFFSET : Int = 8

///|
/// Offset of memory_base in JITContext
pub const CTX_MEMORY_BASE_OFFSET : Int = 16

///|
/// Offset of memory_size in JITContext
pub const CTX_MEMORY_SIZE_OFFSET : Int = 24

// ============ Reserved Registers ============

///|
/// Register holding context pointer (callee-saved)
pub const REG_CONTEXT : Int = 20

///|
/// Register holding cached memory base
pub const REG_MEMORY_BASE : Int = 21

///|
/// Register holding cached memory size
pub const REG_MEMORY_SIZE : Int = 22

///|
/// Register holding extra results buffer pointer
pub const REG_EXTRA_RESULTS : Int = 23

///|
/// Register holding indirect table pointer
pub const REG_INDIRECT_TABLE : Int = 24

// ============ Parameter Passing ============

///|
/// First register for user parameters (new ABI: X0)
pub const PARAM_BASE_REG : Int = 0

///|
/// Maximum number of parameters in registers
pub const MAX_REG_PARAMS : Int = 8

///|
/// First register for float parameters (D0)
pub const FLOAT_PARAM_BASE_REG : Int = 0

///|
/// Maximum number of float parameters in registers
pub const MAX_FLOAT_REG_PARAMS : Int = 8

// ============ Legacy ABI Constants (for compatibility) ============
// Old ABI: X0=func_table, X1=mem_base, X2=mem_size, X3-X10=params

///|
/// First register for user parameters (old ABI: X3)
pub const LEGACY_PARAM_BASE_REG : Int = 3

///|
/// Maximum number of parameters in registers (old ABI)
pub const LEGACY_MAX_REG_PARAMS : Int = 8

// ============ Scratch Registers ============

///|
/// Primary scratch register for code emission
pub const SCRATCH_REG_1 : Int = 16

///|
/// Secondary scratch register (used for br_table, etc.)
pub const SCRATCH_REG_2 : Int = 17

// ============ ABI Version ============

///|
/// Current ABI version
/// v1: Legacy ABI with X0-X2 for context
/// v2: New ABI with X20 for context pointer
pub const ABI_VERSION : Int = 2

// ============ Register Usage in AAPCS64 ============

///|
/// AAPCS64 parameter registers (arguments)
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
/// AAPCS64 return registers
pub fn aapcs64_ret_gprs() -> Array[PReg] {
  [{ index: 0, class: Int }, { index: 1, class: Int }] // x0, x1
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
/// X8-X15 are available for allocation.
/// X16-X17 (IP0/IP1) are reserved for linker/code emission scratch.
pub fn allocatable_scratch_regs() -> Array[PReg] {
  [
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
/// Callee-saved registers available for allocation (must be saved/restored)
/// X20-X22 are reserved for func_table, memory_base, memory_size
/// X24 is reserved for indirect_table_ptr
/// In ABI v2, X19 is reserved for context_ptr preservation across JIT-to-JIT calls
pub fn allocatable_callee_saved_regs() -> Array[PReg] {
  if ABI_VERSION == 2 {
    // v2 ABI: X19 is reserved for context_ptr preservation
    [
      { index: 23, class: Int },
      { index: 25, class: Int },
      { index: 26, class: Int },
      { index: 27, class: Int },
      { index: 28, class: Int },
    ]
  } else {
    // v1 ABI: X19 is allocatable
    [
      { index: 19, class: Int },
      { index: 23, class: Int },
      { index: 25, class: Int },
      { index: 26, class: Int },
      { index: 27, class: Int },
      { index: 28, class: Int },
    ]
  }
}

///|
/// AAPCS64 floating-point argument registers
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
pub fn aapcs64_ret_fprs() -> Array[PReg] {
  [
    { index: 0, class: Float64 },
    { index: 1, class: Float64 },
    { index: 2, class: Float64 },
    { index: 3, class: Float64 },
  ]
}

///|
/// Registers clobbered by function calls (caller-saved)
/// These are registers that the caller must assume are destroyed after a call.
/// For our JIT ABI: X0-X7 (args/return), X8 (scratch), X9-X17 (used by call)
/// Also D0-D7 for floating-point
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
/// Floating-point registers clobbered by function calls
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
  ]
}

///|
/// Callee-saved floating-point registers (D8-D15 in AAPCS64)
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
