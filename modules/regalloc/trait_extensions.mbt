///|
pub extend AllocationEdit with Debug::{to_repr}

///|
pub extend AllocationEdit with Eq::{not_equal, equal}

///|
pub extend AllocationPlan with Debug::{to_repr}

///|
pub extend AllocationPlan with Show::{to_string, output}

///|
pub extend BundleAllocationStatistics with Debug::{to_repr}

///|
pub extend BundleAllocationStatistics with Eq::{not_equal, equal}

///|
pub extend DenseCfgEdges with Debug::{to_repr}

///|
pub extend DenseLiveSets with Debug::{to_repr}

///|
pub extend EditPosition with Debug::{to_repr}

///|
pub extend EditPosition with Eq::{not_equal, equal}

///|
pub extend EditPosition with Hash::{hash, hash_combine}

///|
pub extend LiveRange with Debug::{to_repr}

///|
pub extend LiveRangeSet with Debug::{to_repr}

///|
pub extend Location with Debug::{to_repr}

///|
pub extend Location with Eq::{not_equal, equal}

///|
pub extend OperandAssignment with Debug::{to_repr}

///|
pub extend OperandAssignment with Eq::{not_equal, equal}

///|
pub extend ProgramPoint with Debug::{to_repr}

///|
pub extend ProgramPoint with Eq::{not_equal, equal}

///|
pub extend ProgramRange with Debug::{to_repr}

///|
pub extend ProgramRange with Eq::{not_equal, equal}

///|
pub extend RegallocPhase with Debug::{to_repr}

///|
pub extend RegallocPhase with Eq::{not_equal, equal}

///|
pub extend RegallocPhase with Show::{to_string, output}

///|
pub extend SpillSlotReservation with Debug::{to_repr}

///|
pub extend SpillSlotReservation with Eq::{not_equal, equal}

///|
pub extend SpillSlotSpec with Debug::{to_repr}

///|
pub extend SpillSlotSpec with Eq::{not_equal, equal}

///|
pub extend UseKind with Debug::{to_repr}

///|
pub extend UseKind with Eq::{not_equal, equal}

///|
pub extend UsePosition with Debug::{to_repr}

///|
pub extend UsePosition with Eq::{not_equal, equal}

///|
pub extend VerifyError with Debug::{to_repr}

///|
