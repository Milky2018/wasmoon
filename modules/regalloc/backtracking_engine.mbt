///|
fn[P] append_backtracking_probe_phase(
  out : Array[P],
  regs : Array[P],
  scan_limit : Int,
  offset : Int,
  skip_reg : P?,
  same_reg : (P, P) -> Bool,
) -> Unit {
  let n = regs.length()
  if n == 0 {
    return
  }
  let phase_scan_limit = if scan_limit < n { scan_limit } else { n }
  let phase_offset = (offset % n + n) % n
  let mut scanned = 0
  for i in 0..<n {
    if scanned >= phase_scan_limit {
      break
    }
    let preg = regs[(phase_offset + i) % n]
    if skip_reg is Some(skip) && same_reg(preg, skip) {
      continue
    }
    scanned += 1
    out.push(preg)
  }
}

///|
pub fn[P] plan_backtracking_probe_order(
  available_regs : Array[P],
  caller_saved_regs : Array[P],
  callee_saved_regs : Array[P],
  prefer_caller_saved : Bool,
  scan_limit : Int,
  offset : Int,
  skip_reg : P?,
  same_reg : (P, P) -> Bool,
) -> Array[P] {
  let out : Array[P] = []
  let limit = if scan_limit < available_regs.length() {
    scan_limit
  } else {
    available_regs.length()
  }
  if prefer_caller_saved {
    append_backtracking_probe_phase(
      out, caller_saved_regs, limit, offset, skip_reg, same_reg,
    )
    append_backtracking_probe_phase(
      out, callee_saved_regs, limit, offset, skip_reg, same_reg,
    )
  } else {
    append_backtracking_probe_phase(
      out, available_regs, limit, offset, skip_reg, same_reg,
    )
  }
  out
}

///|
pub fn[P, Q] try_backtracking_single_pass_register(
  available_regs : Array[P],
  caller_saved_regs : Array[P],
  callee_saved_regs : Array[P],
  spans : Array[OrderedSpan[Q]],
  hint_reg : P?,
  prefer_caller_saved : Bool,
  scan_limit : Int,
  offset : Int,
  same_reg : (P, P) -> Bool,
  has_conflict_on_reg : (P, Array[OrderedSpan[Q]]) -> Bool,
) -> P? {
  if available_regs.is_empty() {
    return None
  }
  if hint_reg is Some(hint) {
    for preg in available_regs {
      if same_reg(preg, hint) {
        if !has_conflict_on_reg(preg, spans) {
          return Some(preg)
        }
        break
      }
    }
  }
  let probe_order = plan_backtracking_probe_order(
    available_regs, caller_saved_regs, callee_saved_regs, prefer_caller_saved, scan_limit,
    offset, hint_reg, same_reg,
  )
  for preg in probe_order {
    if !has_conflict_on_reg(preg, spans) {
      return Some(preg)
    }
  }
  None
}

///|
pub(all) struct BacktrackingAllocationAttempt[P, Q] {
  reg : P?
  evicted_ids : Array[Int]
  split : (Q, P)?
}

///|
pub fn[P, Q] try_backtracking_eviction_register(
  available_regs : Array[P],
  caller_saved_regs : Array[P],
  callee_saved_regs : Array[P],
  spans : Array[OrderedSpan[Q]],
  current_weight : Int,
  hint_reg : P?,
  prefer_caller_saved : Bool,
  scan_limit : Int,
  offset : Int,
  same_reg : (P, P) -> Bool,
  to_policy_reg : (P) -> PhysicalReg,
  occupied_for_reg : (P) -> Array[BacktrackingOccupiedSpan[Q]],
  compare_points : (Q, Q) -> Int,
) -> BacktrackingAllocationAttempt[P, Q] {
  let no_evictions : Array[Int] = []
  if available_regs.is_empty() {
    return { reg: None, evicted_ids: no_evictions, split: None }
  }
  let mut best_reg : P? = None
  let mut best_conflict_cost : Int? = None
  let best_conflicts : Array[Int] = []
  let mut best_split_cost : Int? = None
  let mut best_split : (Q, P)? = None
  let probe_order = plan_backtracking_probe_order(
    available_regs,
    caller_saved_regs,
    callee_saved_regs,
    prefer_caller_saved,
    scan_limit,
    offset,
    None,
    same_reg,
  )
  for preg in probe_order {
    let cutoff = eviction_cutoff(best_conflict_cost, best_split_cost)
    let result = scan_backtracking_conflicts_with_cutoff(
      spans,
      occupied_for_reg(preg),
      current_weight,
      cutoff,
    )
    if result.rejected {
      continue
    }
    if result.conflict_ids.is_empty() {
      return { reg: Some(preg), evicted_ids: no_evictions, split: None }
    }
    if result.first_conflict_point is Some(point) {
      let best_split_point = match best_split {
        Some((existing_point, _)) => Some(existing_point)
        None => None
      }
      if should_take_backtracking_split_candidate(
          best_split_cost,
          best_split_point,
          result.max_conflict_weight,
          point,
          compare_points,
        ) {
        best_split_cost = Some(result.max_conflict_weight)
        best_split = Some((point, preg))
      }
    }
    if should_take_eviction_candidate(
        best_conflict_cost,
        match best_reg {
          Some(current_best) => Some(to_policy_reg(current_best))
          None => None
        },
        result.max_conflict_weight,
        to_policy_reg(preg),
        match hint_reg {
          Some(hint) => Some(to_policy_reg(hint))
          None => None
        },
      ) {
      best_reg = Some(preg)
      best_conflict_cost = Some(result.max_conflict_weight)
      best_conflicts.clear()
      for conflict_id in result.conflict_ids {
        best_conflicts.push(conflict_id)
      }
    }
  }
  if best_reg is Some(preg) {
    if best_conflict_cost is Some(cost) && current_weight > cost {
      return { reg: Some(preg), evicted_ids: best_conflicts, split: None }
    }
  }
  { reg: None, evicted_ids: no_evictions, split: best_split }
}

///|
pub fn[B, R, P] run_backtracking_allocation_loop(
  queue : BacktrackingQueue[R],
  bundle_attempts : Array[Int],
  bundle_retry_limit : Int,
  enable_backtracking : Bool,
  bundle_count : Int,
  get_bundle : (Int) -> B,
  bundle_done : (B) -> Bool,
  bundle_is_pinned : (B) -> Bool,
  bundle_has_fixed_constraint : (B) -> Bool,
  bundle_must_force_spill : (B) -> Bool,
  hint_for_bundle : (B, R?) -> R?,
  try_backtracking : (B, R?) -> (R?, (P, R)?),
  try_single_pass : (B, R?) -> R?,
  record_allocation : (B, R) -> Unit,
  split_bundle : (B, (P, R)?) -> Unit,
  force_spill : (B) -> Unit,
) -> Unit {
  let max_iterations = allocation_iteration_limit(bundle_count)
  let mut iterations = 0
  while queue.length() > 0 && iterations < max_iterations {
    iterations += 1
    let entry = match queue.pop() {
      Some(e) => e
      None => break
    }
    let bundle = get_bundle(entry.bundle_id)
    let hint = hint_for_bundle(bundle, entry.hint_preg)
    if bundle_done(bundle) {
      continue
    }
    if entry.bundle_id >= 0 && entry.bundle_id < bundle_attempts.length() {
      bundle_attempts[entry.bundle_id] = bundle_attempts[entry.bundle_id] + 1
      if should_force_spill_after_retry(
          bundle_attempts[entry.bundle_id],
          bundle_retry_limit,
          bundle_is_pinned(bundle),
          bundle_has_fixed_constraint(bundle),
        ) {
        force_spill(bundle)
        continue
      }
    }
    if bundle_must_force_spill(bundle) {
      force_spill(bundle)
      continue
    }
    if enable_backtracking {
      let (alloc_reg, split_opt) = try_backtracking(bundle, hint)
      if alloc_reg is Some(reg) {
        record_allocation(bundle, reg)
        continue
      }
      split_bundle(bundle, split_opt)
      continue
    }
    if try_single_pass(bundle, hint) is Some(reg) {
      record_allocation(bundle, reg)
      continue
    }
    if !bundle_is_pinned(bundle) && !bundle_has_fixed_constraint(bundle) {
      force_spill(bundle)
      continue
    }
    split_bundle(bundle, None)
  }
}
