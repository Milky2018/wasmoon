///|
pub(all) struct BundleSplitRange {
  range_id : Int
  start : ProgramPoint?
  end : ProgramPoint?
} derive(Eq, Debug)

///|
pub(all) enum BundleSplitPlan {
  Split(Array[Int], Array[Int])
  Minimal
  SpillWhole
} derive(Debug)

///|
pub fn plan_bundle_split(
  ranges : Array[BundleSplitRange],
  split_point : ProgramPoint?,
  block_order : Array[Int],
  spillset_split_count : Int,
  max_splits_per_spillset : Int,
) -> BundleSplitPlan {
  if spillset_split_count >= max_splits_per_spillset {
    return Minimal
  }
  guard split_point is Some(point) else { return SpillWhole }
  let before_ranges : Array[Int] = []
  let after_ranges : Array[Int] = []
  for range in ranges {
    if range.end is Some(end_point) {
      if end_point.compare_with_order(point, block_order) <= 0 {
        before_ranges.push(range.range_id)
      } else if range.start is Some(start_point) {
        if start_point.compare_with_order(point, block_order) >= 0 {
          after_ranges.push(range.range_id)
        } else {
          after_ranges.push(range.range_id)
        }
      } else {
        after_ranges.push(range.range_id)
      }
    } else {
      after_ranges.push(range.range_id)
    }
  }
  if before_ranges.is_empty() || after_ranges.is_empty() {
    Minimal
  } else {
    Split(before_ranges, after_ranges)
  }
}
