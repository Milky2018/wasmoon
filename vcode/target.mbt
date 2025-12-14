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
  get_preg(Self, @abi.RegClass, Int) -> @abi.PReg?
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
  class : @abi.RegClass,
  index : Int,
) -> @abi.PReg? {
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
pub fn AArch64Regs::x0(_self : AArch64Regs) -> @abi.PReg {
  { index: 0, class: Int }
}

///|
pub fn AArch64Regs::x1(_self : AArch64Regs) -> @abi.PReg {
  { index: 1, class: Int }
}

///|
pub fn AArch64Regs::x2(_self : AArch64Regs) -> @abi.PReg {
  { index: 2, class: Int }
}

///|
pub fn AArch64Regs::x3(_self : AArch64Regs) -> @abi.PReg {
  { index: 3, class: Int }
}

///|
pub fn AArch64Regs::x4(_self : AArch64Regs) -> @abi.PReg {
  { index: 4, class: Int }
}

///|
pub fn AArch64Regs::x5(_self : AArch64Regs) -> @abi.PReg {
  { index: 5, class: Int }
}

///|
pub fn AArch64Regs::x6(_self : AArch64Regs) -> @abi.PReg {
  { index: 6, class: Int }
}

///|
pub fn AArch64Regs::x7(_self : AArch64Regs) -> @abi.PReg {
  { index: 7, class: Int }
}

// Frame pointer (x29) and link register (x30)

///|
pub fn AArch64Regs::fp(_self : AArch64Regs) -> @abi.PReg {
  { index: 29, class: Int }
}

///|
pub fn AArch64Regs::lr(_self : AArch64Regs) -> @abi.PReg {
  { index: 30, class: Int }
}

// Stack pointer (x31 when used as SP, but typically handled specially)
// Note: x31 as zero register (xzr) is handled by the instruction encoding

// Floating-point registers

///|
pub fn AArch64Regs::d0(_self : AArch64Regs) -> @abi.PReg {
  { index: 0, class: Float64 }
}

///|
pub fn AArch64Regs::d1(_self : AArch64Regs) -> @abi.PReg {
  { index: 1, class: Float64 }
}

///|
pub fn AArch64Regs::d2(_self : AArch64Regs) -> @abi.PReg {
  { index: 2, class: Float64 }
}

///|
pub fn AArch64Regs::d3(_self : AArch64Regs) -> @abi.PReg {
  { index: 3, class: Float64 }
}

///|
pub fn AArch64Regs::d4(_self : AArch64Regs) -> @abi.PReg {
  { index: 4, class: Float64 }
}

///|
pub fn AArch64Regs::d5(_self : AArch64Regs) -> @abi.PReg {
  { index: 5, class: Float64 }
}

///|
pub fn AArch64Regs::d6(_self : AArch64Regs) -> @abi.PReg {
  { index: 6, class: Float64 }
}

///|
pub fn AArch64Regs::d7(_self : AArch64Regs) -> @abi.PReg {
  { index: 7, class: Float64 }
}
