///|
pub struct ABISettings {
  ///
  /// When true, reserve the embedding context register role supplied through
  /// `EmbeddingRegRoles`.
  reserve_embedding_context : Bool
}

///|
pub fn ABISettings::default() -> ABISettings {
  { reserve_embedding_context: true }
}
