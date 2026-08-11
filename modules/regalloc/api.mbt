///|
pub(all) enum AllocatorStrategy {
  Backtracking
  Fast
} derive(Eq, Debug)

///|
pub impl Show for AllocatorStrategy with fn output(self, logger) {
  match self {
    Backtracking => logger.write_string("Backtracking")
    Fast => logger.write_string("Fast")
  }
}

///|
/// The allocator's internal phases, in the order they run.
///
/// Reported through `RegallocConfig::observer` so a caller that owns a clock
/// can attribute compile time per phase. This module stays clock-free: it
/// only says which phase it is entering (ISS-371).
pub(all) enum RegallocPhase {
  LiveRanges
  SegmentConstruction
  BundleFormation
  BundleAllocation
  FastAllocation
  HomeAssignment
  OperandAssignment
  EdgeTransfers
  EditResolution
  Verification
} derive(Eq, Debug)

///|
pub impl Show for RegallocPhase with fn output(self, logger) {
  logger.write_string(
    match self {
      LiveRanges => "live_ranges"
      SegmentConstruction => "segment_construction"
      BundleFormation => "bundle_formation"
      BundleAllocation => "bundle_allocation"
      FastAllocation => "fast_allocation"
      HomeAssignment => "home_assignment"
      OperandAssignment => "operand_assignment"
      EdgeTransfers => "edge_transfers"
      EditResolution => "edit_resolution"
      Verification => "verification"
    },
  )
}

///|
pub struct RegallocConfig {
  strategy : AllocatorStrategy
  verify : Bool
  // Called as each phase begins, and once with None when the last one ends.
  // Absent by default so the allocator pays nothing when nobody is measuring.
  observer : ((RegallocPhase?) -> Unit)?
}

///|
pub fn RegallocConfig::RegallocConfig(
  strategy? : AllocatorStrategy = Backtracking,
  verify? : Bool = true,
  observer? : ((RegallocPhase?) -> Unit)? = None,
) -> RegallocConfig {
  { strategy, verify, observer }
}

///|
pub fn RegallocConfig::strategy(self : RegallocConfig) -> AllocatorStrategy {
  self.strategy
}

///|
pub fn RegallocConfig::verify(self : RegallocConfig) -> Bool {
  self.verify
}

///|
/// Announce that `phase` is starting, or that the last one has finished.
pub fn RegallocConfig::enter_phase(
  self : RegallocConfig,
  phase : RegallocPhase?,
) -> Unit {
  if self.observer is Some(notify) {
    notify(phase)
  }
}
