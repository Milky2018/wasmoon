///|
/// Target-compilation boundaries exposed to an embedding-owned observer.
///
/// The observer must not mutate compiler inputs from inside the callback.
pub(all) enum TargetCompileEvent {
  RegallocStarted
  // A named phase inside register allocation began; the previous one, if any,
  // ended at the same instant. `RegallocFinished` closes the last phase.
  // Carried as a name so the allocator stays free of timing concerns and this
  // enum stays free of the allocator's internal vocabulary (ISS-371).
  RegallocPhaseStarted(String)
  // The allocator's own phases are done. The span from here to
  // `RegallocFinished` is the embedding's own post-allocation work —
  // translating the plan and any target-level checking — and belongs to
  // neither the allocator nor an allocator phase.
  RegallocPhasesFinished
  RegallocFinished(AllocationStatistics)
  FramePlanningStarted
  FramePlanningFinished
  EmissionStarted
  EmissionFinished
} derive(Eq, Debug)
