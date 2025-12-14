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
