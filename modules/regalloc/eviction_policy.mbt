///|
pub fn eviction_cutoff(
  best_conflict_cost : Int?,
  best_split_cost : Int?,
) -> Int? {
  match (best_conflict_cost, best_split_cost) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
}

///|
pub fn should_take_eviction_candidate(
  best_conflict_cost : Int?,
  best_preg : PhysicalReg?,
  candidate_cost : Int,
  candidate_preg : PhysicalReg,
  hint_preg : PhysicalReg?,
) -> Bool {
  match best_conflict_cost {
    None => true
    Some(existing_cost) =>
      if candidate_cost < existing_cost {
        true
      } else if candidate_cost == existing_cost {
        match (hint_preg, best_preg) {
          (Some(hint), Some(current_best)) =>
            candidate_preg == hint && current_best != hint
          _ => false
        }
      } else {
        false
      }
  }
}

///|
pub fn should_take_split_candidate(
  best_split_cost : Int?,
  best_split_point : ProgramPoint?,
  candidate_cost : Int,
  candidate_point : ProgramPoint,
  block_order : Array[Int],
) -> Bool {
  match (best_split_cost, best_split_point) {
    (None, None) => true
    (Some(existing_cost), Some(existing_point)) =>
      if candidate_cost < existing_cost {
        true
      } else {
        candidate_cost == existing_cost &&
        candidate_point.compare_with_order(existing_point, block_order) > 0
      }
    _ => false
  }
}
