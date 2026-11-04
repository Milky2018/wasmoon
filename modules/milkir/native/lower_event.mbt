///|
/// Direct-lowering boundaries exposed to observation-only embeddings.
///
/// The observer must not mutate the source or constructed function while
/// lowering is running.
#derive(Debug, Eq)
pub(all) enum NativeLowerEvent {
  PreparationStarted(name~ : String)
  InputValidationStarted
  TargetConstructionStarted
  NativeLoweringFinished
}
