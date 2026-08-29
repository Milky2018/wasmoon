///|
/// The allocator's internal phases, in the order they run.
///
/// Reported through `RegallocConfig::observer` so a caller that owns a clock
/// can attribute compile time per phase. This module stays clock-free: it
/// only says which phase it is entering (ISS-371).
pub(all) enum RegallocPhase {
  InputValidation
  LiveRanges
  SegmentConstruction
  BundleFormation
  BundleAllocation
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
      InputValidation => "input_validation"
      LiveRanges => "live_ranges"
      SegmentConstruction => "segment_construction"
      BundleFormation => "bundle_formation"
      BundleAllocation => "bundle_allocation"
      HomeAssignment => "home_assignment"
      OperandAssignment => "operand_assignment"
      EdgeTransfers => "edge_transfers"
      EditResolution => "edit_resolution"
      Verification => "verification"
    },
  )
}

///|
/// Deterministic work counters for the backtracking bundle loop.
///
/// These count allocator decisions rather than elapsed time, so callers can
/// compare runs without making this reusable module own a clock.
pub struct BundleAllocationStatistics {
  mut queue_pops : Int
  mut register_probes : Int
  mut occupied_segments_scanned : Int
  mut conflicts : Int
  mut evictions : Int
  mut bundle_splits : Int
  mut second_chance_attempts : Int
  mut max_queue_length : Int
} derive(Eq, Debug)

///|
fn BundleAllocationStatistics::new() -> BundleAllocationStatistics {
  {
    queue_pops: 0,
    register_probes: 0,
    occupied_segments_scanned: 0,
    conflicts: 0,
    evictions: 0,
    bundle_splits: 0,
    second_chance_attempts: 0,
    max_queue_length: 0,
  }
}

///|
pub fn BundleAllocationStatistics::queue_pops(
  self : BundleAllocationStatistics,
) -> Int {
  self.queue_pops
}

///|
pub fn BundleAllocationStatistics::register_probes(
  self : BundleAllocationStatistics,
) -> Int {
  self.register_probes
}

///|
pub fn BundleAllocationStatistics::occupied_segments_scanned(
  self : BundleAllocationStatistics,
) -> Int {
  self.occupied_segments_scanned
}

///|
pub fn BundleAllocationStatistics::conflicts(
  self : BundleAllocationStatistics,
) -> Int {
  self.conflicts
}

///|
pub fn BundleAllocationStatistics::evictions(
  self : BundleAllocationStatistics,
) -> Int {
  self.evictions
}

///|
pub fn BundleAllocationStatistics::bundle_splits(
  self : BundleAllocationStatistics,
) -> Int {
  self.bundle_splits
}

///|
pub fn BundleAllocationStatistics::second_chance_attempts(
  self : BundleAllocationStatistics,
) -> Int {
  self.second_chance_attempts
}

///|
pub fn BundleAllocationStatistics::max_queue_length(
  self : BundleAllocationStatistics,
) -> Int {
  self.max_queue_length
}

///|
pub struct RegallocConfig {
  verify : Bool
  // Called as each phase begins, and once with None when the last one ends.
  // Absent by default so the allocator pays nothing when nobody is measuring.
  observer : ((RegallocPhase?) -> Unit)?
  statistics_observer : ((BundleAllocationStatistics) -> Unit)?
}

///|
/// Reusable storage for a serial sequence of register-allocation jobs.
///
/// A session is intentionally not thread-safe. Independent compilation jobs
/// must own independent sessions; callers compiling functions serially may
/// reuse one session to retain scratch capacity between functions.
pub struct AllocationSession {
  priv context_priorities : Array[Int]
  priv context_weights : Array[Int]
  priv context_fixed_constraints : Array[Bool]
  priv context_boundary_costs : Array[Int]
  priv context_minimals : Array[Bool]
  priv context_spill_sets : Array[Int]
  priv segment_owner : Array[Int]
  priv segment_spill_set : Array[Int]
  priv owner_run_count : Array[Int]
  priv occupied_block_order : Array[Int]
  priv occupied_roots : Array[Int]
  priv occupied_left : Array[Int]
  priv occupied_right : Array[Int]
  priv occupied_parent : Array[Int]
  priv occupied_previous : Array[Int]
  priv occupied_next : Array[Int]
  priv occupied_starts : Array[Int64]
  priv occupied_ends : Array[Int64]
  priv occupied_stack : Array[Int]
  priv preferred_by_value : Array[Int]
  priv conflict_marks : Array[Int]
  priv probe_conflicts : Array[Int]
  priv eviction_conflicts : Array[Int]
  priv register_order : Array[Int]
  priv register_order_marks : Array[Bool]
  priv physical_register_indexes : Array[Int]
  priv queue_items : Array[Int]
  priv queue_priorities : Array[Int]
  priv queue_weights : Array[Int]
  priv queue_in_queue : Array[Bool]
  priv queue_hints : Array[Int]
}

///|
pub fn RegallocConfig::RegallocConfig(
  verify? : Bool = true,
  observer? : ((RegallocPhase?) -> Unit)? = None,
  statistics_observer? : ((BundleAllocationStatistics) -> Unit)? = None,
) -> RegallocConfig {
  { verify, observer, statistics_observer, }
}

///|
fn RegallocConfig::report_bundle_statistics(
  self : RegallocConfig,
  statistics : BundleAllocationStatistics,
) -> Unit {
  if self.statistics_observer is Some(notify) {
    notify(statistics)
  }
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
