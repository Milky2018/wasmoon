///|
/// Target-compilation boundaries exposed to an embedding-owned observer.
///
/// The observer must not mutate compiler inputs from inside the callback.
pub(all) enum TargetCompileEvent {
  RegallocStarted
  RegallocFinished(AllocationStatistics)
  FramePlanningStarted
  FramePlanningFinished
  EmissionStarted
  EmissionFinished
} derive(Eq, Debug)
