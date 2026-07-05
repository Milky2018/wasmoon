// Target Architecture Interface
// Defines abstractions for target-specific code generation

///|
/// Target ISA - interface for instruction set architecture
/// Each target (AArch64, x86-64, etc.) implements this trait
pub(open) trait TargetISA {
  /// Get the name of the target
  fn name(Self) -> String
  /// Get available general-purpose registers
  fn gpr_count(Self) -> Int
  /// Get available floating-point registers
  fn fpr_count(Self) -> Int
  /// Get the register for a given index in the register class
  fn get_preg(Self, @abi.RegClass, Int) -> @abi.PReg?
  /// Get the size of a pointer in bytes
  fn pointer_size(Self) -> Int
}

///|
/// Platform ABI - how to interface with the platform's C runtime
/// This determines register usage, stack layout, and calling semantics
/// for external (non-WASM) function calls.
///
/// Note: This is different from vcode/instr/CallConv which describes
/// internal WASM call vs C call at the instruction level.
#warnings("-unused_constructor")
pub enum PlatformABI {
  /// System V AMD64 ABI (Linux, macOS on x86-64)
  /// - Args: RDI, RSI, RDX, RCX, R8, R9, then stack
  /// - Returns: RAX, RDX
  /// - Caller-saved: RAX, RCX, RDX, RSI, RDI, R8-R11
  /// - Callee-saved: RBX, RBP, R12-R15
  SystemV_AMD64
  /// Windows x64 calling convention
  /// - Args: RCX, RDX, R8, R9, then stack (shadow space required)
  /// - Returns: RAX
  /// - Caller-saved: RAX, RCX, RDX, R8-R11
  /// - Callee-saved: RBX, RBP, RDI, RSI, R12-R15
  Windows_x64
  /// ARM64 AAPCS calling convention (Linux, Android)
  /// - Args: X0-X7 (int), D0-D7 (float), then stack
  /// - Returns: X0-X1, D0-D3
  /// - Caller-saved: X0-X17, D0-D7, D16-D31
  /// - Callee-saved: X19-X28, D8-D15
  AAPCS64
  /// Apple ARM64 calling convention (macOS, iOS)
  /// - Same as AAPCS64 with minor variations
  /// - X18 is reserved (platform register)
  Apple_ARM64
}

///|
fn PlatformABI::to_string(self : PlatformABI) -> String {
  match self {
    SystemV_AMD64 => "sysv_amd64"
    Windows_x64 => "windows_x64"
    AAPCS64 => "aapcs64"
    Apple_ARM64 => "apple_arm64"
  }
}

///|
pub impl Show for PlatformABI with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Get the platform ABI for the current build target
/// Currently only Apple ARM64 is supported
pub fn PlatformABI::current() -> PlatformABI {
  // TODO: Use conditional compilation when available
  // For now, we only support Apple ARM64 (macOS on Apple Silicon)
  Apple_ARM64
}

///|
/// Check if the platform uses 16-byte stack alignment
pub fn PlatformABI::requires_16_byte_stack_align(self : PlatformABI) -> Bool {
  match self {
    SystemV_AMD64 | Windows_x64 | AAPCS64 | Apple_ARM64 => true
  }
}

///|
/// Get the number of integer argument registers
pub fn PlatformABI::int_arg_regs(self : PlatformABI) -> Int {
  match self {
    SystemV_AMD64 => 6 // RDI, RSI, RDX, RCX, R8, R9
    Windows_x64 => 4 // RCX, RDX, R8, R9
    AAPCS64 | Apple_ARM64 => 8 // X0-X7
  }
}

///|
/// Get the number of float argument registers
pub fn PlatformABI::float_arg_regs(self : PlatformABI) -> Int {
  match self {
    SystemV_AMD64 => 8 // XMM0-XMM7
    Windows_x64 => 4 // XMM0-XMM3
    AAPCS64 | Apple_ARM64 => 8 // D0-D7
  }
}

// ============ AArch64 Target ============

///|
/// AArch64 target ISA
struct AArch64 {
  name : String
}

///|
pub fn AArch64::new() -> AArch64 {
  { name: "aarch64" }
}

///|
pub impl TargetISA for AArch64 with fn name(self) -> String {
  self.name
}

///|
pub impl TargetISA for AArch64 with fn gpr_count(_self) -> Int {
  31 // x0-x30, x31 is zero register
}

///|
pub impl TargetISA for AArch64 with fn fpr_count(_self) -> Int {
  32 // v0-v31
}

///|
pub impl TargetISA for AArch64 with fn get_preg(
  _self,
  class : @abi.RegClass,
  index : Int,
) -> @abi.PReg? {
  if class is Int {
    if index >= 0 && index < 31 {
      Some({ index, class: Int })
    } else {
      None
    }
    // Vector uses same V0-V31 registers as floats on AArch64
  } else if index >= 0 && index < 32 {
    Some({ index, class })
  } else {
    None
  }
}

///|
pub impl TargetISA for AArch64 with fn pointer_size(_self) -> Int {
  8 // 64-bit pointers
}
