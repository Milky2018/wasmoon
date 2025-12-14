// Target Architecture Interface
// Defines abstractions for target-specific code generation

///|
/// Target ISA - interface for instruction set architecture
/// Each target (AArch64, x86-64, etc.) implements this trait
pub(open) trait TargetISA {
  /// Get the name of the target
  name(Self) -> String
  /// Get available general-purpose registers
  gpr_count(Self) -> Int
  /// Get available floating-point registers
  fpr_count(Self) -> Int
  /// Get the register for a given index in the register class
  get_preg(Self, RegClass, Int) -> PReg?
  /// Get the size of a pointer in bytes
  pointer_size(Self) -> Int
}

///|
/// Calling convention - how function calls are made
#warnings("-unused_constructor")
pub enum CallConv {
  /// System V AMD64 ABI (Linux, macOS on x86-64)
  SystemV
  /// Windows x64 calling convention
  WindowsFastcall
  /// ARM64 AAPCS calling convention
  Aapcs64
  /// WebAssembly calling convention
  Wasm
}

///|
fn CallConv::to_string(self : CallConv) -> String {
  match self {
    SystemV => "system_v"
    WindowsFastcall => "windows_fastcall"
    Aapcs64 => "aapcs64"
    Wasm => "wasm"
  }
}

///|
pub impl Show for CallConv with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ AArch64 Target ============

///|
/// AArch64 target ISA
pub(all) struct AArch64 {
  name : String
}

///|
pub fn AArch64::new() -> AArch64 {
  { name: "aarch64" }
}

///|
pub impl TargetISA for AArch64 with name(self) -> String {
  self.name
}

///|
pub impl TargetISA for AArch64 with gpr_count(_self) -> Int {
  31 // x0-x30, x31 is zero register
}

///|
pub impl TargetISA for AArch64 with fpr_count(_self) -> Int {
  32 // v0-v31
}

///|
pub impl TargetISA for AArch64 with get_preg(
  _self,
  class : RegClass,
  index : Int,
) -> PReg? {
  match class {
    Int =>
      if index >= 0 && index < 31 {
        Some({ index, class: Int })
      } else {
        None
      }
    Float32 | Float64 =>
      if index >= 0 && index < 32 {
        Some({ index, class })
      } else {
        None
      }
  }
}

///|
pub impl TargetISA for AArch64 with pointer_size(_self) -> Int {
  8 // 64-bit pointers
}

// ============ AArch64 Register Definitions ============

///|
/// AArch64 register names and roles
pub(all) struct AArch64Regs {
  placeholder : Int // Placeholder field
}

///|
pub fn AArch64Regs::new() -> AArch64Regs {
  { placeholder: 0 }
}

// General-purpose registers

///|
pub fn AArch64Regs::x0(_self : AArch64Regs) -> PReg {
  { index: 0, class: Int }
}

///|
pub fn AArch64Regs::x1(_self : AArch64Regs) -> PReg {
  { index: 1, class: Int }
}

///|
pub fn AArch64Regs::x2(_self : AArch64Regs) -> PReg {
  { index: 2, class: Int }
}

///|
pub fn AArch64Regs::x3(_self : AArch64Regs) -> PReg {
  { index: 3, class: Int }
}

///|
pub fn AArch64Regs::x4(_self : AArch64Regs) -> PReg {
  { index: 4, class: Int }
}

///|
pub fn AArch64Regs::x5(_self : AArch64Regs) -> PReg {
  { index: 5, class: Int }
}

///|
pub fn AArch64Regs::x6(_self : AArch64Regs) -> PReg {
  { index: 6, class: Int }
}

///|
pub fn AArch64Regs::x7(_self : AArch64Regs) -> PReg {
  { index: 7, class: Int }
}

// Frame pointer (x29) and link register (x30)

///|
pub fn AArch64Regs::fp(_self : AArch64Regs) -> PReg {
  { index: 29, class: Int }
}

///|
pub fn AArch64Regs::lr(_self : AArch64Regs) -> PReg {
  { index: 30, class: Int }
}

// Stack pointer (x31 when used as SP, but typically handled specially)
// Note: x31 as zero register (xzr) is handled by the instruction encoding

// Floating-point registers

///|
pub fn AArch64Regs::d0(_self : AArch64Regs) -> PReg {
  { index: 0, class: Float64 }
}

///|
pub fn AArch64Regs::d1(_self : AArch64Regs) -> PReg {
  { index: 1, class: Float64 }
}

///|
pub fn AArch64Regs::d2(_self : AArch64Regs) -> PReg {
  { index: 2, class: Float64 }
}

///|
pub fn AArch64Regs::d3(_self : AArch64Regs) -> PReg {
  { index: 3, class: Float64 }
}

///|
pub fn AArch64Regs::d4(_self : AArch64Regs) -> PReg {
  { index: 4, class: Float64 }
}

///|
pub fn AArch64Regs::d5(_self : AArch64Regs) -> PReg {
  { index: 5, class: Float64 }
}

///|
pub fn AArch64Regs::d6(_self : AArch64Regs) -> PReg {
  { index: 6, class: Float64 }
}

///|
pub fn AArch64Regs::d7(_self : AArch64Regs) -> PReg {
  { index: 7, class: Float64 }
}

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
  if @abi.ABI_VERSION == 2 {
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
