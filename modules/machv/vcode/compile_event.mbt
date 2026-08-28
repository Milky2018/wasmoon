///|
/// Deterministic counters for the allocator's bundle-probing loop.
pub(all) struct RegallocLoopStatistics {
  queue_pops : Int
  register_probes : Int
  occupied_segments_scanned : Int
  conflicts : Int
  evictions : Int
  bundle_splits : Int
  second_chance_attempts : Int
  max_queue_length : Int
} derive(Eq, Debug)

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
  RegallocLoopMeasured(RegallocLoopStatistics)
  RegallocFinished(AllocationStatistics)
  FramePlanningStarted
  FramePlanningFinished
  EmissionStarted
  EmissionFinished
} derive(Eq, Debug)
