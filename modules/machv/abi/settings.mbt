///|
/// Backend ABI settings shared by lowering, register allocation, and emission.
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
  /// When true, reserve the embedding context register role supplied through
  /// `EmbeddingRegRoles`.
  reserve_embedding_context : Bool
  ///
  /// Target calling convention.
  call_conv : CallConv
}

///|
pub fn ABISettings::default() -> ABISettings {
  { reserve_embedding_context: true, call_conv: AppleAarch64 }
}
