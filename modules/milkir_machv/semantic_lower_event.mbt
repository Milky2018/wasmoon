///|
/// Semantic-lowering boundaries exposed to observation-only embeddings.
///
/// The observer must not mutate the source or constructed function while
/// lowering is running.
pub(all) enum SemanticLowerEvent {
  InputValidationStarted
  SemanticConstructionStarted
  CleanupPhaseStarted(@semantic.MandatoryCleanupPhase)
  SemanticLoweringFinished
} derive(Debug, Eq)
