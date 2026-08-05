///|
/// The bundle plan's self-checks, driven with plans that violate them (ISS-398).
///
/// These eleven checks used to `abort`, so exercising one killed the test
/// process instead of failing it — which is why none of them had a test. They
/// now raise `VerifyError::InvalidPlan`, and every case below would have been
/// a SIGABRT before.

///|
/// Run `validate` and hand back whatever it raised.
fn validate_plan_error(
  plan : ProductionBundlePlan,
  range_count : Int,
  segment_count : Int,
) -> VerifyError? {
  try {
    plan.validate(range_count, segment_count)
    None
  } catch {
    error => Some(error)
  }
}

///|
/// The plan the corrupted ones below are derived from: two ranges and two
/// segments split across two bundles, mapped consistently.
fn well_formed_bundle_plan() -> ProductionBundlePlan {
  {
    range_to_bundle: [0, 1],
    segment_to_bundle: [0, 1],
    bundle_ranges: [[0], [1]],
    bundle_segments: [[0], [1]],
  }
}

///|
test "bundle plan: a well-formed plan raises nothing" {
  debug_inspect(
    validate_plan_error(well_formed_bundle_plan(), 2, 2),
    content="None",
  )
}

///|
test "bundle plan: a range count that disagrees with the mapping" {
  debug_inspect(
    validate_plan_error(well_formed_bundle_plan(), 3, 2),
    content=(
      #|Some(InvalidPlan(message="invalid production bundle plan dimensions"))
    ),
  )
}

///|
test "bundle plan: differing range and segment bundle counts" {
  debug_inspect(
    validate_plan_error(
      {
        range_to_bundle: [0, 1],
        segment_to_bundle: [0, 1],
        bundle_ranges: [[0], [1]],
        bundle_segments: [[0], [1], []],
      },
      2,
      2,
    ),
    content=(
      #|Some(InvalidPlan(message="invalid production bundle plan dimensions"))
    ),
  )
}

///|
/// Bundle 1 claims range 0, which `range_to_bundle` says belongs to bundle 0.
test "bundle plan: a range claimed by the wrong bundle" {
  debug_inspect(
    validate_plan_error(
      {
        range_to_bundle: [0, 1],
        segment_to_bundle: [0, 1],
        bundle_ranges: [[0], [0]],
        bundle_segments: [[0], [1]],
      },
      2,
      2,
    ),
    content=(
      #|Some(InvalidPlan(message="invalid production bundle range mapping for range 0 in bundle 1"))
    ),
  )
}

///|
/// Range 1 is in no bundle at all.
test "bundle plan: a range no bundle claims" {
  debug_inspect(
    validate_plan_error(
      {
        range_to_bundle: [0, 0],
        segment_to_bundle: [0, 1],
        bundle_ranges: [[0], []],
        bundle_segments: [[0], [1]],
      },
      2,
      2,
    ),
    content=(
      #|Some(InvalidPlan(message="incomplete production bundle range mapping for range 1"))
    ),
  )
}

///|
test "bundle plan: a segment claimed by the wrong bundle" {
  debug_inspect(
    validate_plan_error(
      {
        range_to_bundle: [0, 1],
        segment_to_bundle: [0, 1],
        bundle_ranges: [[0], [1]],
        bundle_segments: [[0], [0]],
      },
      2,
      2,
    ),
    content=(
      #|Some(InvalidPlan(message="invalid production bundle segment mapping for segment 0 in bundle 1"))
    ),
  )
}

///|
test "bundle plan: a segment no bundle claims" {
  debug_inspect(
    validate_plan_error(
      {
        range_to_bundle: [0, 1],
        segment_to_bundle: [0, 0],
        bundle_ranges: [[0], [1]],
        bundle_segments: [[0], []],
      },
      2,
      2,
    ),
    content=(
      #|Some(InvalidPlan(message="incomplete production bundle segment mapping for segment 1"))
    ),
  )
}

///|
/// A segment id past the end of the segment array.
test "bundle plan: a segment id outside the plan" {
  debug_inspect(
    validate_plan_error(
      {
        range_to_bundle: [0, 1],
        segment_to_bundle: [0, 1],
        bundle_ranges: [[0], [1]],
        bundle_segments: [[0], [7]],
      },
      2,
      2,
    ),
    content=(
      #|Some(InvalidPlan(message="invalid production bundle segment mapping for segment 7 in bundle 1"))
    ),
  )
}
