///|
/// Cranelift-style backend settings (minimal subset).
///
/// This is intentionally tiny for Phase 1: it only carries the settings we need
/// to begin matching Cranelift’s AArch64 ABI, especially the pinned-reg toggle.
///
/// Reference:
/// - wasmtime/cranelift `settings::Flags::enable_pinned_reg()`
/// - wasmtime/cranelift `isa::CallConv::AppleAarch64`
#warnings("-unused_constructor")
pub enum CallConv {
  ///
  /// Apple’s AArch64 ABI variant.
  AppleAarch64
  ///
  /// Generic AAPCS64 / SystemV-like convention.
  SystemV
}

///|
pub struct ABISettings {
  ///
  /// When true, reserve a pinned register for VMContext (Cranelift: enable_pinned_reg).
  enable_pinned_reg : Bool
  ///
  /// Target calling convention.
  call_conv : CallConv
}

///|
pub fn ABISettings::default() -> ABISettings {
  { enable_pinned_reg: true, call_conv: AppleAarch64 }
}
