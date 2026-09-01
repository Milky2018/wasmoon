///|
/// Direct-lowering boundaries exposed to observation-only embeddings.
///
/// The observer must not mutate the source or constructed function while
/// lowering is running.
pub(all) enum NativeLowerEvent {
  InputValidationStarted
  TargetConstructionStarted
  NativeLoweringFinished
} derive(Debug, Eq)
