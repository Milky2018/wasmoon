// MachV adapter for the reusable backtracking allocator core in `regalloc`.
// This file owns MachV projection/materialization; allocation policy and
// state-machine decisions must stay in `regalloc`.

///|
/// Check if two register classes are compatible
fn reg_class_compatible(a : @abi.RegClass, b : @abi.RegClass) -> Bool {
  match (a, b) {
    (Int, Int) => true
    (Float32, Float32) => true
    (Float32, Float64) => true
    (Float64, Float32) => true
    (Float64, Float64) => true
    (Vector, Vector) => true
    _ => false
  }
}

///|
fn abi_class_to_regalloc_policy(class : @abi.RegClass) -> @regalloc.RegClass {
  match class {
    Int => Int
    Float32 | Float64 => Float
    Vector => Vector
  }
}

///|
fn abi_preg_to_regalloc_policy(preg : @abi.PReg) -> @regalloc.PhysicalReg {
  { id: preg.index, class: abi_class_to_regalloc_policy(preg.class) }
}

///|
fn same_abi_preg(lhs : @abi.PReg, rhs : @abi.PReg) -> Bool {
  lhs.class == rhs.class && lhs.index == rhs.index
}

///|
fn reserve_abi_spill_slot(
  next_slot : Int,
  class : @abi.RegClass,
) -> @regalloc.SpillSlotReservation {
  @regalloc.reserve_spill_slot(next_slot, abi_class_to_regalloc_policy(class))
}

///|
fn abi_class_tag_for_constraint(class : @abi.RegClass) -> Int {
  match class {
    Int => 0
    Float32 => 1
    Float64 => 2
    Vector => 3
  }
}

///|
fn abi_class_from_constraint_tag(tag : Int) -> @abi.RegClass {
  match tag {
    0 => Int
    1 => Float32
    2 => Float64
    3 => Vector
    _ => Int
  }
}

///|
fn backtracking_move_loc_to_machv(
  loc : BacktrackingMoveLoc,
  class_tag : Int,
) -> Loc {
  match loc {
    BacktrackingMoveReg(preg) => Reg(preg)
    BacktrackingMoveSpill(slot) => {
      ignore(class_tag)
      Spill(slot)
    }
  }
}

///|
/// Register allocation algorithm policy.
///
/// - Backtracking: Ion-style backtracking + eviction/splitting (better codegen).
/// - SinglePass: no eviction/backtracking, spills earlier (faster compile).
pub type RegallocAlgorithm = @backtracking.RegallocAlgorithm

///|
type OrderedSpan = @backtracking.OrderedSpan[ProgPoint]

///|
type MergeSpan = @backtracking.MergeSpan[ProgPointRange]

///|
type SpillSetInfo = @backtracking.SpillSetInfo[
  @abi.RegClass,
  ProgPointRange,
  ProgPoint,
]

///|
type BacktrackingAllocationLoc = @backtracking.BacktrackingAllocationLoc[
  @abi.PReg,
]

///|
type BacktrackingConstraintOperand = @backtracking.BacktrackingConstraintOperand[
  @abi.PReg,
]

///|
type BacktrackingFixedConstraint = @backtracking.BacktrackingFixedConstraint[
  @abi.PReg,
]

///|
type BacktrackingFixedConstraintInst = @backtracking.BacktrackingFixedConstraintInst[
  @abi.PReg,
]

///|
type BacktrackingMoveLoc = @backtracking.BacktrackingMoveLoc[@abi.PReg]

///|
/// MachV adapter state for the reusable backtracking allocator core.
priv struct BacktrackingAllocator {
  // Core data
  ranges : LiveRangeSet
  bundles : BundleSet

  // Physical register occupancy: preg.index -> list of occupied ranges.
  //
  // Kept as direct-index arrays (instead of maps) to avoid hash lookups in the
  // hot conflict-scan path.
  // Each entry stores (bundle_id, span) so eviction/removal cannot accidentally
  // remove spans that belong to a different bundle with identical boundaries.
  int_reg_allocs : Array[Array[(Int, OrderedSpan)]]
  float_reg_allocs : Array[Array[(Int, OrderedSpan)]]

  // Per-bundle flattened/sorted span cache (bundle-id indexed).
  // This mirrors regalloc2's use of ordered per-bundle ranges for conflict
  // scans while avoiding hash lookups in hot allocation loops.
  bundle_span_cache : Array[Array[OrderedSpan]?]

  // Priority queue of bundles to process
  queue : @backtracking.BacktrackingQueue[@abi.PReg]

  // Cranelift-style spillset hint: remember last successful preg for an
  // "original" bundle (spillset), and prefer it for split pieces.
  spillsets : @backtracking.BacktrackingSpillsetState[@abi.PReg]
  // Cache fixed-constraint-derived hints per bundle to avoid rescanning
  // all bundle uses on every queue pop.
  bundle_hint_cache : @backtracking.BacktrackingHintCache[@abi.PReg]

  // Configuration
  int_regs : Array[@abi.PReg]
  float_regs : Array[@abi.PReg]
  vector_regs : Array[@abi.PReg]
  callee_saved_int : Array[@abi.PReg]
  callee_saved_float : Array[@abi.PReg]
  int_caller_saved : Array[@abi.PReg]
  float_caller_saved : Array[@abi.PReg]
  split_probe_limit : Int
  bundle_retry_limit : Int
  enable_backtracking : Bool

  // Block order for comparison (O(1) lookup)
  block_order : FixedArray[Int]
  // Approximate loop-depth per block (pre-computed once).
  loop_depths : Array[Int]
  // Dense point order base offset per block-order index.
  block_point_base : Array[Int]

  // Reference to function for constraint lookups
  func : @machv.Function
  bundle_attempts : Array[Int]
}

///|
/// Heap push into the allocator queue.
fn BacktrackingAllocator::queue_push(
  self : BacktrackingAllocator,
  bundle_id : Int,
  prio : Int,
  hint_preg : @abi.PReg?,
) -> Unit {
  self.queue.push(bundle_id, prio, hint_preg)
}

///|
fn max_preg_index(regs : Array[@abi.PReg]) -> Int {
  let mut max_idx = -1
  for preg in regs {
    if preg.index > max_idx {
      max_idx = preg.index
    }
  }
  max_idx
}

///|
fn make_reg_alloc_table(cap : Int) -> Array[Array[(Int, OrderedSpan)]] {
  @backtracking.make_backtracking_alloc_table(cap)
}

///|
fn make_bool_table(cap : Int) -> Array[Bool] {
  @backtracking.make_backtracking_bool_table(cap)
}

///|
fn BacktrackingAllocator::BacktrackingAllocator(
  func : @machv.Function,
  ranges : LiveRangeSet,
  bundles : BundleSet,
  int_regs : Array[@abi.PReg],
  float_regs : Array[@abi.PReg],
  vector_regs : Array[@abi.PReg],
  callee_saved_int : Array[@abi.PReg],
  callee_saved_float : Array[@abi.PReg],
  algorithm? : RegallocAlgorithm = Backtracking,
) -> BacktrackingAllocator {
  let loop_depths = compute_loop_depths(func)
  let num_blocks = func.blocks.length()
  let block_order = ranges.block_order
  let block_idx_by_order : Array[Int] = Array::make(num_blocks, 0)
  for block_idx in 0..<num_blocks {
    block_idx_by_order[block_order[block_idx]] = block_idx
  }
  let block_point_base : Array[Int] = Array::make(num_blocks, 0)
  let mut point_cursor = 0
  for ord in 0..<num_blocks {
    block_point_base[ord] = point_cursor
    let block_idx = block_idx_by_order[ord]
    let block_len = func.blocks[block_idx].insts.length()
    point_cursor = point_cursor + (block_len + 2) * 2
  }
  // Keep register probing/regalloc retries aligned with regalloc2 behavior:
  // no large-function downscaling on the main allocation search.
  let split_probe_limit = 1 << 30
  let bundle_retry_limit = 1 << 30
  let enable_backtracking = algorithm.enable_backtracking()
  let int_max = {
    let mut max_idx = max_preg_index(int_regs)
    let callee_max = max_preg_index(callee_saved_int)
    if callee_max > max_idx {
      max_idx = callee_max
    }
    max_idx
  }
  let float_max = {
    let mut max_idx = max_preg_index(float_regs)
    let vector_max = max_preg_index(vector_regs)
    if vector_max > max_idx {
      max_idx = vector_max
    }
    let callee_max = max_preg_index(callee_saved_float)
    if callee_max > max_idx {
      max_idx = callee_max
    }
    max_idx
  }
  let int_is_callee_saved = make_bool_table(int_max + 1)
  for preg in callee_saved_int {
    if preg.index >= 0 && preg.index < int_is_callee_saved.length() {
      int_is_callee_saved[preg.index] = true
    }
  }
  let float_is_callee_saved = make_bool_table(float_max + 1)
  for preg in callee_saved_float {
    if preg.index >= 0 && preg.index < float_is_callee_saved.length() {
      float_is_callee_saved[preg.index] = true
    }
  }
  let int_caller_saved : Array[@abi.PReg] = []
  for preg in int_regs {
    if preg.index >= 0 &&
      preg.index < int_is_callee_saved.length() &&
      !int_is_callee_saved[preg.index] {
      int_caller_saved.push(preg)
    }
  }
  let float_caller_saved : Array[@abi.PReg] = []
  for preg in float_regs {
    if preg.index >= 0 &&
      preg.index < float_is_callee_saved.length() &&
      !float_is_callee_saved[preg.index] {
      float_caller_saved.push(preg)
    }
  }
  {
    ranges,
    bundles,
    int_reg_allocs: make_reg_alloc_table(int_max + 1),
    float_reg_allocs: make_reg_alloc_table(float_max + 1),
    bundle_span_cache: Array::make(bundles.length(), None),
    queue: BacktrackingQueue(bundles.length()),
    spillsets: BacktrackingSpillsetState(bundles.length()),
    bundle_hint_cache: BacktrackingHintCache(bundles.length()),
    int_regs,
    float_regs,
    vector_regs,
    callee_saved_int,
    callee_saved_float,
    int_caller_saved,
    float_caller_saved,
    split_probe_limit,
    bundle_retry_limit,
    enable_backtracking,
    block_order,
    loop_depths,
    block_point_base,
    func,
    bundle_attempts: Array::make(bundles.length(), 0),
  }
}

///|
fn BacktrackingAllocator::point_order(
  self : BacktrackingAllocator,
  point : ProgPoint,
) -> Int {
  let block_ord = self.block_order[point.block]
  let pos_ord = match point.pos {
    Before => 0
    After => 1
  }
  self.block_point_base[block_ord] + (point.inst + 1) * 2 + pos_ord
}

///|
/// Queue priority follows regalloc2 Ion's bundle priority:
/// total covered instruction length of all ranges in this bundle.
fn BacktrackingAllocator::bundle_queue_prio(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Int {
  ignore(self)
  bundle.prio
}

///|
/// Spill weight follows regalloc2 Ion: sum(use weights) divided by bundle prio.
fn BacktrackingAllocator::recompute_bundle_spill_weight(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Int {
  let total = compute_spill_weight(bundle, self.ranges, self.loop_depths)
  let prio = self.bundle_queue_prio(bundle)
  if prio <= 0 {
    total
  } else {
    total / prio
  }
}

///|
/// Derive a hint preg from fixed-reg constraints inside a bundle.
///
/// This is a Cranelift-like *hint* only: it helps reduce reg-to-reg moves by
/// encouraging allocation into the same preg required by operand constraints,
/// but it is never treated as a hard constraint for the whole bundle.
fn BacktrackingAllocator::constraint_hint_preg(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> @abi.PReg? {
  let avail_regs = self.get_available_regs(bundle)
  if avail_regs.is_empty() {
    return None
  }
  let mut max_idx = -1
  for preg in avail_regs {
    if preg.index > max_idx {
      max_idx = preg.index
    }
  }
  if max_idx < 0 {
    return None
  }
  let avail_idx = Array::make(max_idx + 1, false)
  let counts = Array::make(max_idx + 1, 0)
  for preg in avail_regs {
    avail_idx[preg.index] = true
  }

  // Count how often each fixed preg appears in uses.
  for range_id in bundle.range_ids {
    let range = self.ranges.get(range_id)
    for use_pos in range.uses {
      if use_pos.constraint is FixedReg(preg) && preg.class == bundle.reg_class {
        if preg.index >= 0 &&
          preg.index < avail_idx.length() &&
          avail_idx[preg.index] {
          counts[preg.index] = counts[preg.index] + 1
        }
      }
    }
  }

  let mut best_idx = -1
  let mut best_cnt = 0
  for preg in avail_regs {
    let idx = preg.index
    let cnt = counts[idx]
    if cnt > best_cnt ||
      (cnt == best_cnt && cnt > 0 && (best_idx < 0 || idx < best_idx)) {
      best_idx = idx
      best_cnt = cnt
    }
  }
  if best_idx >= 0 && best_cnt > 0 {
    Some({ index: best_idx, class: bundle.reg_class })
  } else {
    None
  }
}

///|
fn BacktrackingAllocator::constraint_hint_preg_cached(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> @abi.PReg? {
  if bundle.id >= 0 && self.bundle_hint_cache.is_ready(bundle.id) {
    return self.bundle_hint_cache.hint(bundle.id)
  }
  let hint = self.constraint_hint_preg(bundle)
  self.bundle_hint_cache.set(bundle.id, hint)
  hint
}

///|
/// Initialize the priority queue with all bundles
fn BacktrackingAllocator::init_queue(self : BacktrackingAllocator) -> Unit {
  self.queue.clear()
  // Recompute spill weights, enqueue by bundle priority.
  for i in 0..<self.bundles.length() {
    let bundle = self.bundles.get(i)
    bundle.prio = bundle.total_length(self.ranges)
    bundle.spill_weight = self.recompute_bundle_spill_weight(bundle)
    let hint_preg = if self.enable_backtracking {
      self.constraint_hint_preg_cached(bundle)
    } else {
      None
    }
    self.queue_push(i, self.bundle_queue_prio(bundle), hint_preg)
  }
}

///|
/// Get the occupancy map for a register class
fn BacktrackingAllocator::get_reg_allocs(
  self : BacktrackingAllocator,
  class : @abi.RegClass,
) -> Array[Array[(Int, OrderedSpan)]] {
  match class {
    Int => self.int_reg_allocs
    Float32 | Float64 | Vector => self.float_reg_allocs
  }
}

///|
/// Flatten a bundle to sorted spans (cached by bundle id).
fn BacktrackingAllocator::bundle_sorted_spans(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Array[OrderedSpan] {
  if bundle.id >= 0 &&
    bundle.id < self.bundle_span_cache.length() &&
    self.bundle_span_cache[bundle.id] is Some(spans) {
    return spans
  }
  let spans : Array[OrderedSpan] = []
  match bundle.merged_ranges {
    Some(raw_spans) =>
      for raw_span in raw_spans {
        spans.push({
          start: raw_span.start,
          start_ord: self.point_order(raw_span.start),
          end_ord: self.point_order(raw_span.end),
        })
      }
    None => {
      for range_id in bundle.range_ids {
        let range = self.ranges.get(range_id)
        for raw_span in range.ranges {
          spans.push({
            start: raw_span.start,
            start_ord: self.point_order(raw_span.start),
            end_ord: self.point_order(raw_span.end),
          })
        }
      }
      spans.sort_by(fn(a, b) {
        if a.start_ord < b.start_ord {
          -1
        } else if a.start_ord > b.start_ord {
          1
        } else {
          0
        }
      })
    }
  }
  if bundle.id >= 0 && bundle.id < self.bundle_span_cache.length() {
    self.bundle_span_cache[bundle.id] = Some(spans)
  }
  spans
}

///|
fn BacktrackingAllocator::has_conflict_on_preg_with_spans(
  self : BacktrackingAllocator,
  spans : Array[OrderedSpan],
  preg : @abi.PReg,
) -> Bool {
  let allocs = self.get_reg_allocs(preg.class)
  if preg.index < 0 || preg.index >= allocs.length() {
    return false
  }
  let occupied = allocs[preg.index]
  if occupied.is_empty() || spans.is_empty() {
    return false
  }
  @backtracking.has_backtracking_span_conflict(spans, occupied)
}

///|
/// Fast conflict probe: return true as soon as one overlap is found.
fn BacktrackingAllocator::has_conflict_on_preg(
  self : BacktrackingAllocator,
  bundle : Bundle,
  preg : @abi.PReg,
) -> Bool {
  let spans = self.bundle_sorted_spans(bundle)
  self.has_conflict_on_preg_with_spans(spans, preg)
}

///|
/// Get available registers for a bundle
fn BacktrackingAllocator::get_available_regs(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Array[@abi.PReg] {
  let available = match bundle.reg_class {
    Int => self.int_regs
    Float32 | Float64 => self.float_regs
    Vector => self.vector_regs
  }
  let callee_saved = match bundle.reg_class {
    Int => self.callee_saved_int
    Float32 | Float64 => self.callee_saved_float
    Vector => []
  }
  let crosses_call = bundle.crosses_call(self.ranges)
  if crosses_call {
    match abi_class_to_regalloc_policy(bundle.reg_class) {
      Int | Float => callee_saved
      Vector => []
    }
  } else {
    available
  }
}

///|
fn BacktrackingAllocator::caller_saved_regs_for_class(
  self : BacktrackingAllocator,
  class : @abi.RegClass,
) -> Array[@abi.PReg] {
  match class {
    Int => self.int_caller_saved
    Float32 | Float64 => self.float_caller_saved
    Vector => []
  }
}

///|
fn BacktrackingAllocator::callee_saved_regs_for_class(
  self : BacktrackingAllocator,
  class : @abi.RegClass,
) -> Array[@abi.PReg] {
  match class {
    Int => self.callee_saved_int
    Float32 | Float64 => self.callee_saved_float
    Vector => []
  }
}

///|
/// Check if a register is free for all ranges in a bundle
fn BacktrackingAllocator::is_reg_free(
  self : BacktrackingAllocator,
  preg : @abi.PReg,
  bundle : Bundle,
) -> Bool {
  !self.has_conflict_on_preg(bundle, preg)
}

///|
fn BacktrackingAllocator::occupied_spans_for_preg(
  self : BacktrackingAllocator,
  preg : @abi.PReg,
) -> Array[@backtracking.BacktrackingOccupiedSpan[ProgPoint]] {
  let projected : Array[@backtracking.BacktrackingOccupiedSpan[ProgPoint]] = []
  let allocs = self.get_reg_allocs(preg.class)
  if preg.index < 0 || preg.index >= allocs.length() {
    return projected
  }
  let occupied = allocs[preg.index]
  for item in occupied {
    let other = self.bundles.get(item.0)
    projected.push({
      owner_id: item.0,
      span: item.1,
      owner_weight: other.spill_weight,
      owner_pinned: other.is_pinned,
    })
  }
  projected
}

///|
/// Record allocation of a register to a bundle
fn BacktrackingAllocator::record_allocation(
  self : BacktrackingAllocator,
  bundle : Bundle,
  preg : @abi.PReg,
) -> Unit {
  let allocs = self.get_reg_allocs(preg.class)
  while allocs.length() <= preg.index {
    allocs.push([])
  }
  let occupied = allocs[preg.index]
  let spans = self.bundle_sorted_spans(bundle)
  if spans.length() == 1 {
    let span = spans[0]
    let mut lo = 0
    let mut hi = occupied.length()
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      if occupied[mid].1.start_ord <= span.start_ord {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    occupied.insert(lo, (bundle.id, span))
  } else if occupied.is_empty() {
    let new_occupied : Array[(Int, OrderedSpan)] = []
    for span in spans {
      new_occupied.push((bundle.id, span))
    }
    allocs[preg.index] = new_occupied
  } else {
    let new_occupied : Array[(Int, OrderedSpan)] = []
    let mut i = 0
    let mut j = 0
    while i < occupied.length() && j < spans.length() {
      if occupied[i].1.start_ord <= spans[j].start_ord {
        new_occupied.push(occupied[i])
        i = i + 1
      } else {
        new_occupied.push((bundle.id, spans[j]))
        j = j + 1
      }
    }
    while i < occupied.length() {
      new_occupied.push(occupied[i])
      i = i + 1
    }
    while j < spans.length() {
      new_occupied.push((bundle.id, spans[j]))
      j = j + 1
    }
    allocs[preg.index] = new_occupied
  }
  for range_id in bundle.range_ids {
    let range = self.ranges.get(range_id)
    range.allocation = Reg(preg)
  }
  bundle.allocation = Reg(preg)

  // Update spillset hint (Cranelift-style): this helps split pieces prefer
  // the same preg, reducing move traffic and improving locality.
  self.spillsets.record_hint(bundle.spillset_id, preg)
}

///|
/// Remove allocation of a bundle (for eviction)
fn BacktrackingAllocator::remove_allocation(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Unit {
  if bundle.allocation is Reg(preg) {
    let allocs = self.get_reg_allocs(preg.class)
    if preg.index >= 0 && preg.index < allocs.length() {
      let occupied = allocs[preg.index]
      // Remove ranges belonging to this bundle.
      let new_occupied : Array[(Int, OrderedSpan)] = []
      for occ in occupied {
        if occ.0 != bundle.id {
          new_occupied.push(occ)
        }
      }
      allocs[preg.index] = new_occupied
    }

    // Clear allocation
    for range_id in bundle.range_ids {
      let range = self.ranges.get(range_id)
      range.allocation = Unallocated
    }
    bundle.allocation = Unallocated
  }
}

///|
/// Try to allocate a register for a bundle
/// Returns the allocated register if successful
fn BacktrackingAllocator::try_allocate(
  self : BacktrackingAllocator,
  bundle : Bundle,
  hint_preg : @abi.PReg?,
) -> @abi.PReg? {
  let avail_regs = self.get_available_regs(bundle)
  let spans = self.bundle_sorted_spans(bundle)
  let start_inst = if !spans.is_empty() { spans[0].start.inst } else { 0 }
  let prefer_caller_saved = @backtracking.should_prefer_caller_saved_for_backtracking(
    abi_class_to_regalloc_policy(bundle.reg_class),
    self.enable_backtracking,
    bundle.crosses_call(self.ranges),
  )
  @backtracking.try_backtracking_single_pass_register(
    avail_regs,
    self.caller_saved_regs_for_class(bundle.reg_class),
    self.callee_saved_regs_for_class(bundle.reg_class),
    spans,
    hint_preg,
    prefer_caller_saved,
    self.split_probe_limit,
    bundle.id + start_inst,
    same_abi_preg,
    fn(preg, spans) { self.has_conflict_on_preg_with_spans(spans, preg) },
  )
}

///|
/// Try to find a register for a bundle in one scan:
/// - If a register is conflict-free, allocate directly.
/// - Otherwise, keep both best legal eviction candidate and split candidate.
/// Returns:
/// - allocated preg on success;
/// - split point + reg hint for caller-side split fallback when no eviction wins.
fn BacktrackingAllocator::try_evict(
  self : BacktrackingAllocator,
  bundle : Bundle,
  hint_preg : @abi.PReg?,
) -> (@abi.PReg?, (ProgPoint, @abi.PReg)?) {
  let avail_regs = self.get_available_regs(bundle)
  let spans = self.bundle_sorted_spans(bundle)
  let prefer_caller_saved = @backtracking.should_prefer_caller_saved_for_backtracking(
    abi_class_to_regalloc_policy(bundle.reg_class),
    self.enable_backtracking,
    bundle.crosses_call(self.ranges),
  )
  let attempt = @backtracking.try_backtracking_eviction_register(
    avail_regs,
    self.caller_saved_regs_for_class(bundle.reg_class),
    self.callee_saved_regs_for_class(bundle.reg_class),
    spans,
    bundle.spill_weight,
    hint_preg,
    prefer_caller_saved,
    self.split_probe_limit,
    bundle.id,
    same_abi_preg,
    abi_preg_to_regalloc_policy,
    fn(preg) { self.occupied_spans_for_preg(preg) },
    fn(a, b) { a.compare_with_order(b, self.block_order) },
  )
  if attempt.reg is Some(preg) {
    for conflict_id in attempt.evicted_ids {
      let conflict = self.bundles.get(conflict_id)
      self.remove_allocation(conflict)
      self.queue_push(conflict_id, self.bundle_queue_prio(conflict), None)
    }
    return (Some(preg), None)
  }
  (None, attempt.split)
}

///|
/// Split a bundle at conflict points
fn BacktrackingAllocator::split_bundle(
  self : BacktrackingAllocator,
  bundle : Bundle,
  split_opt : (ProgPoint, @abi.PReg)?,
) -> Unit {
  let split_hint = match split_opt {
    Some((_, hint)) => Some(hint)
    None => None
  }
  let spillset_id = bundle.spillset_id
  let split_limit_reached = self.spillsets.split_limit_reached(spillset_id)
  let split_point = match split_opt {
    Some((point, _)) => Some(point)
    None => None
  }
  let split_ranges : Array[@backtracking.BacktrackingSplitRange[ProgPoint]] = []
  for range_id in bundle.range_ids {
    let range = self.ranges.get(range_id)
    split_ranges.push({
      range_id,
      start: range.start(self.block_order),
      end: range.end(self.block_order),
    })
  }
  let plan = @backtracking.plan_backtracking_bundle_split(
    split_ranges,
    split_point,
    split_limit_reached,
    fn(end_point, point) {
      end_point.compare_with_order(point, self.block_order) <= 0
    },
    fn(start_point, point) {
      start_point.compare_with_order(point, self.block_order) >= 0
    },
  )
  if split_opt is Some(_) && !split_limit_reached {
    self.spillsets.record_split(spillset_id)
  }

  match plan {
    BacktrackingMinimal => {
      self.split_into_minimal_bundles(bundle, split_hint)
      return
    }
    BacktrackingSpillWhole => {
      let spill_bundle = self.bundles.get_or_create_spill_bundle(bundle)
      let slot = spill_bundle.slot
      bundle.allocation = Spill(slot)
      for range_id in bundle.range_ids {
        let range = self.ranges.get(range_id)
        range.allocation = Spill(slot)
      }
    }
    BacktrackingSplit(before_ranges, after_ranges) => {
      let split_hint_reg = match split_hint {
        Some(hint) => hint
        None => abort("missing split hint for split plan")
      }
      let spill_bundle = self.bundles.get_or_create_spill_bundle(bundle)

      // Before bundle
      let before_bundle = Bundle::Bundle(
        self.bundles.bundles.length(),
        bundle.reg_class,
      )
      before_bundle.spill_bundle_id = spill_bundle.id
      before_bundle.spillset_id = bundle.spillset_id
      for range_id in before_ranges {
        before_bundle.add_range(range_id)
        self.ranges.get(range_id).bundle_id = before_bundle.id
      }
      before_bundle.prio = before_bundle.total_length(self.ranges)
      before_bundle.spill_weight = self.recompute_bundle_spill_weight(
        before_bundle,
      )
      self.bundles.add_bundle(before_bundle)
      self.queue.push_bundle_slot()
      self.bundle_attempts.push(0)
      self.bundle_span_cache.push(None)
      self.bundle_hint_cache.push_bundle_slot()
      spill_bundle.add_bundle(before_bundle.id)
      self.queue_push(
        before_bundle.id,
        self.bundle_queue_prio(before_bundle),
        Some(split_hint_reg),
      )

      // After bundle
      let after_bundle = Bundle::Bundle(
        self.bundles.bundles.length(),
        bundle.reg_class,
      )
      after_bundle.spill_bundle_id = spill_bundle.id
      after_bundle.spillset_id = bundle.spillset_id
      for range_id in after_ranges {
        after_bundle.add_range(range_id)
        self.ranges.get(range_id).bundle_id = after_bundle.id
      }
      after_bundle.prio = after_bundle.total_length(self.ranges)
      after_bundle.spill_weight = self.recompute_bundle_spill_weight(
        after_bundle,
      )
      self.bundles.add_bundle(after_bundle)
      self.queue.push_bundle_slot()
      self.bundle_attempts.push(0)
      self.bundle_span_cache.push(None)
      self.bundle_hint_cache.push_bundle_slot()
      spill_bundle.add_bundle(after_bundle.id)
      self.queue_push(
        after_bundle.id,
        self.bundle_queue_prio(after_bundle),
        Some(split_hint_reg),
      )

      // Mark original bundle as processed (it's been split)
      bundle.allocation = Spill(spill_bundle.slot)
    }
  }
}

///|
fn BacktrackingAllocator::enqueue_single_range_bundle(
  self : BacktrackingAllocator,
  source_bundle : Bundle,
  spill_bundle : SpillBundle,
  range_id : Int,
  hint : @abi.PReg?,
) -> Unit {
  let new_bundle = Bundle::Bundle(
    self.bundles.bundles.length(),
    source_bundle.reg_class,
  )
  new_bundle.spill_bundle_id = spill_bundle.id
  new_bundle.spillset_id = source_bundle.spillset_id
  new_bundle.add_range(range_id)
  self.ranges.get(range_id).bundle_id = new_bundle.id
  new_bundle.prio = new_bundle.total_length(self.ranges)
  new_bundle.spill_weight = self.recompute_bundle_spill_weight(new_bundle)
  self.bundles.add_bundle(new_bundle)
  self.queue.push_bundle_slot()
  self.bundle_attempts.push(0)
  self.bundle_span_cache.push(None)
  self.bundle_hint_cache.push_bundle_slot()
  spill_bundle.add_bundle(new_bundle.id)
  self.queue_push(new_bundle.id, self.bundle_queue_prio(new_bundle), hint)
}

///|
fn BacktrackingAllocator::split_into_minimal_bundles(
  self : BacktrackingAllocator,
  bundle : Bundle,
  hint : @abi.PReg?,
) -> Unit {
  if bundle.range_ids.length() <= 1 {
    self.force_spill_bundle(bundle)
    return
  }
  let spill_bundle = self.bundles.get_or_create_spill_bundle(bundle)
  let mut first = true
  for range_id in bundle.range_ids {
    let child_hint = if first {
      first = false
      hint
    } else {
      None
    }
    self.enqueue_single_range_bundle(bundle, spill_bundle, range_id, child_hint)
  }
  bundle.allocation = Spill(spill_bundle.slot)
}

///|
/// Main allocation loop
fn BacktrackingAllocator::allocate(self : BacktrackingAllocator) -> Unit {
  self.init_queue()
  @backtracking.run_backtracking_allocation_loop(
    self.queue,
    self.bundle_attempts,
    self.bundle_retry_limit,
    self.enable_backtracking,
    self.bundles.length(),
    fn(bundle_id) { self.bundles.get(bundle_id) },
    fn(bundle) { bundle.allocation is Reg(_) || bundle.allocation is Spill(_) },
    fn(bundle) { bundle.is_pinned },
    fn(bundle) { bundle.has_fixed_constraint(self.ranges) },
    fn(bundle) {
      @regalloc.should_force_spill_for_class_and_call(
        abi_class_to_regalloc_policy(bundle.reg_class),
        bundle.crosses_call(self.ranges),
      )
    },
    fn(bundle, entry_hint) {
      match entry_hint {
        Some(preg) => Some(preg)
        None =>
          match self.spillsets.hint(bundle.spillset_id) {
            Some(preg) => Some(preg)
            None =>
              if self.enable_backtracking {
                self.constraint_hint_preg_cached(bundle)
              } else {
                None
              }
          }
      }
    },
    fn(bundle, hint) { self.try_evict(bundle, hint) },
    fn(bundle, hint) { self.try_allocate(bundle, hint) },
    fn(bundle, preg) { self.record_allocation(bundle, preg) },
    fn(bundle, split_opt) { self.split_bundle(bundle, split_opt) },
    fn(bundle) { self.force_spill_bundle(bundle) },
  )
}

///|
/// Generate moves for split bundles that share a spill slot
/// This inserts spills and reloads at the boundaries between split parts
fn BacktrackingAllocator::generate_moves(
  self : BacktrackingAllocator,
) -> Array[RegMove] {
  let moves : Array[RegMove] = []

  // For each spill bundle, check if parts have different allocations
  for spill_bundle in self.bundles.spill_bundles {
    if spill_bundle.bundle_ids.length() < 2 {
      continue
    }

    // Collect all bundles in this spill bundle
    let parts : Array[(Bundle, @abi.PReg?)] = []
    for bundle_id in spill_bundle.bundle_ids {
      let bundle = self.bundles.get(bundle_id)
      let preg = match bundle.allocation {
        Reg(p) => Some(p)
        _ => None
      }
      parts.push((bundle, preg))
    }

    // Generate moves between adjacent parts with different allocations
    // This is a simplified version - a full implementation would track
    // the exact split points and insert moves at those locations
    for i in 0..<(parts.length() - 1) {
      let (bundle1, alloc1) = parts[i]
      let (bundle2, alloc2) = parts[i + 1]
      match (alloc1, alloc2) {
        (Some(preg1), Some(preg2)) =>
          if preg1.index != preg2.index {
            // Need a move from preg1 to preg2 (via spill slot)
            // The actual move insertion happens in apply_allocation
            ignore(bundle1)
            ignore(bundle2)
          }
        (Some(_), None) | (None, Some(_)) =>
          // One part in register, one spilled - needs reload/spill
          // Handled by apply_allocation
          ()
        (None, None) =>
          // Both spilled to same slot - no move needed
          ()
      }
    }
  }
  moves
}

///|
fn backtracking_location_for_vreg(
  vreg_id : Int,
  assignment_dense : Array[@abi.PReg?],
  spill_slot_dense : Array[Int],
  result : RegAllocResult,
  max_vreg_id : Int,
) -> BacktrackingAllocationLoc {
  let assigned_opt = if vreg_id >= 0 && vreg_id < max_vreg_id {
    assignment_dense[vreg_id]
  } else {
    result.assignments.get(vreg_id)
  }
  match assigned_opt {
    Some(preg) => BacktrackingReg(preg)
    None => {
      let spill_slot = if vreg_id >= 0 && vreg_id < max_vreg_id {
        spill_slot_dense[vreg_id]
      } else {
        match result.spill_slots.get(vreg_id) {
          Some(slot) => slot
          None => -1
        }
      }
      if spill_slot >= 0 {
        BacktrackingSpill(spill_slot)
      } else {
        BacktrackingUnallocated
      }
    }
  }
}

///|
/// Generate allocation result compatible with existing code
fn BacktrackingAllocator::generate_result(
  self : BacktrackingAllocator,
) -> RegAllocResult {
  // Generate any needed moves for split bundles
  let _moves = self.generate_moves()
  let max_vreg_id = self.func.next_vreg_id
  let range_results : Array[@backtracking.BacktrackingRangeResult[@abi.PReg]] = []
  for i in 0..<self.ranges.length() {
    let range = self.ranges.get(i)
    let allocation : BacktrackingAllocationLoc = match range.allocation {
      Reg(preg) => {
        // Ensure the preg class matches the vreg class. This is important for
        // float registers where the pool uses Float64 but the vreg might be
        // Float32.
        let corrected_preg : @abi.PReg = {
          index: preg.index,
          class: range.vreg.class,
        }
        BacktrackingReg(corrected_preg)
      }
      Spill(slot) => BacktrackingSpill(slot)
      Unallocated => BacktrackingUnallocated
    }
    range_results.push({ vreg_id: range.vreg.id, allocation })
  }
  let generic_result = @backtracking.build_backtracking_allocation_result(
    range_results,
    self.bundles.next_spill_slot,
  )
  let result : RegAllocResult = {
    assignments: {},
    spill_slots: {},
    num_spill_slots: generic_result.num_spill_slots,
    inst_edits: [],
  }
  let assignment_dense : Array[@abi.PReg?] = Array::make(max_vreg_id, None)
  let spill_slot_dense : Array[Int] = Array::make(max_vreg_id, -1)

  for assignment in generic_result.assignments {
    let (vreg_id, preg) = assignment
    result.assignments.set(vreg_id, preg)
    if vreg_id >= 0 && vreg_id < max_vreg_id {
      assignment_dense[vreg_id] = Some(preg)
    }
  }
  for spill in generic_result.spill_slots {
    let (vreg_id, slot) = spill
    result.spill_slots.set(vreg_id, slot)
    if vreg_id >= 0 && vreg_id < max_vreg_id {
      spill_slot_dense[vreg_id] = slot
    }
  }

  // Generate moves for FixedReg constraints.
  for block_idx, block in self.func.blocks {
    for inst_idx, inst in block.insts {
      if inst.use_constraints.is_empty() && inst.def_constraints.is_empty() {
        continue
      }
      let uses : Array[BacktrackingFixedConstraint] = []
      let defs : Array[BacktrackingFixedConstraint] = []
      for i, constraint in inst.use_constraints {
        if constraint is FixedReg(required_preg) {
          let use_reg = inst.uses[i]
          if use_reg is Virtual(vreg) {
            let operand : BacktrackingConstraintOperand = BacktrackingVirtual(
              backtracking_location_for_vreg(
                vreg.id,
                assignment_dense,
                spill_slot_dense,
                result,
                max_vreg_id,
              ),
              abi_class_tag_for_constraint(vreg.class),
            )
            uses.push({ operand, required: required_preg })
          } else if use_reg is Physical(preg) {
            let operand : BacktrackingConstraintOperand = BacktrackingPhysical(
              preg,
              abi_class_tag_for_constraint(preg.class),
            )
            uses.push({ operand, required: required_preg })
          }
        }
      }
      for i, constraint in inst.def_constraints {
        if constraint is FixedReg(required_preg) {
          let def = inst.defs[i]
          if def.reg is Virtual(vreg) {
            let operand : BacktrackingConstraintOperand = BacktrackingVirtual(
              backtracking_location_for_vreg(
                vreg.id,
                assignment_dense,
                spill_slot_dense,
                result,
                max_vreg_id,
              ),
              abi_class_tag_for_constraint(vreg.class),
            )
            defs.push({ operand, required: required_preg })
          }
        }
      }
      if !uses.is_empty() || !defs.is_empty() {
        let constraint_inst : BacktrackingFixedConstraintInst = {
          block_index: block_idx,
          inst_index: inst_idx,
          uses,
          defs,
        }
        let planned = @backtracking.plan_backtracking_fixed_constraint_edits(
          [constraint_inst],
          fn(a, b) { a.index == b.index },
        )
        for planned_edits in planned {
          let edits = InstEdits::InstEdits()
          for mv in planned_edits.before {
            edits.before.push({
              from: backtracking_move_loc_to_machv(mv.from, mv.class_tag),
              to: backtracking_move_loc_to_machv(mv.to, mv.class_tag),
              class: abi_class_from_constraint_tag(mv.class_tag),
            })
          }
          for mv in planned_edits.after {
            edits.after.push({
              from: backtracking_move_loc_to_machv(mv.from, mv.class_tag),
              to: backtracking_move_loc_to_machv(mv.to, mv.class_tag),
              class: abi_class_from_constraint_tag(mv.class_tag),
            })
          }
          result.inst_edits.push(
            (planned_edits.block_index, planned_edits.inst_index, edits),
          )
        }
      }
    }
  }

  // Reuse spill slots across non-overlapping spilled bundles (regalloc2-style).
  //
  // Important: this is a post-allocation compaction step. The allocator
  // initially assigns a distinct spill slot per spill bundle (to keep the
  // allocator logic simple). Here we perform a conservative "slot coloring"
  // based on live-range overlap so that multiple spill bundles can share a
  // physical stack slot when their lifetimes do not overlap.
  //
  // This mirrors regalloc2's concept of assigning spillsets to spillslots
  // (see regalloc2 doc/ION.md), but adapted to MachV's existing BundleSet.
  if self.ranges.length() >= 2000 || self.bundles.next_spill_slot >= 256 {
    return result
  }
  let compacted_spillslots = self.compact_spill_slots(result)
  {
    assignments: result.assignments,
    spill_slots: result.spill_slots,
    num_spill_slots: compacted_spillslots,
    inst_edits: result.inst_edits,
  }
}

///|
/// Compact spill slots by reusing them across non-overlapping spill bundles.
fn BacktrackingAllocator::compact_spill_slots(
  self : BacktrackingAllocator,
  result : RegAllocResult,
) -> Int {
  fn spans_overlap(
    a : Array[ProgPointRange],
    b : Array[ProgPointRange],
    block_order : FixedArray[Int],
  ) -> Bool {
    for ra in a {
      for rb in b {
        if ra.overlaps(rb, block_order) {
          return true
        }
      }
    }
    false
  }

  fn compute_start(
    spans : Array[ProgPointRange],
    block_order : FixedArray[Int],
  ) -> ProgPoint {
    let mut s = spans[0].start
    for i in 1..<spans.length() {
      let p = spans[i].start
      if p.compare_with_order(s, block_order) < 0 {
        s = p
      }
    }
    s
  }

  // 1) Build spillsets keyed by the old spill-slot id.
  let spillsets_by_slot : Map[Int, SpillSetInfo] = {}
  for vreg_id, old_slot in result.spill_slots {
    let range = match self.ranges.get_by_vreg(vreg_id) {
      Some(r) => r
      None => abort("missing LiveRange for spilled vreg \{vreg_id}")
    }
    let info = match spillsets_by_slot.get(old_slot) {
      Some(existing) => existing
      None => {
        // Initialize with a dummy start; we fill it after collecting spans.
        let dummy = range.ranges[0].start
        let created : SpillSetInfo = {
          old_slot,
          reg_class: range.vreg.class,
          spans: [],
          start: dummy,
        }
        spillsets_by_slot.set(old_slot, created)
        created
      }
    }
    // Sanity: a spill slot should not mix register classes.
    if info.reg_class != range.vreg.class {
      abort(
        "spill slot \{old_slot} mixes classes: \{info.reg_class} vs \{range.vreg.class}",
      )
    }
    for span in range.ranges {
      info.spans.push(span)
    }
  }
  if spillsets_by_slot.is_empty() {
    return 0
  }

  // 2) Materialize spillsets and sort by start (linear-scan-friendly).
  let spillsets : Array[SpillSetInfo] = []
  for _, info in spillsets_by_slot {
    // Skip empty (should not happen).
    if info.spans.is_empty() {
      continue
    }
    let start = compute_start(info.spans, self.ranges.block_order)
    spillsets.push({
      old_slot: info.old_slot,
      reg_class: info.reg_class,
      spans: info.spans,
      start,
    })
  }
  spillsets.sort_by(fn(a, b) {
    a.start.compare_with_order(b.start, self.ranges.block_order)
  })

  // 2.5) Build anti-coalesce constraints for block-arg edge copies.
  //
  // Any spilled values participating in the same edge-parallel-copy must keep
  // distinct spill slots after compaction. Otherwise, compaction can collapse
  // logically distinct values onto one stack location at the jump boundary and
  // break SSA block-arg semantics.
  let no_share_edges : Array[@regalloc.SpillSlotNoShareEdge] = []
  let block_id_to_index : Map[Int, Int] = {}
  for i, block in self.func.blocks {
    block_id_to_index.set(block.id, i)
  }
  for pred_block in self.func.blocks {
    if pred_block.terminator is Some(Jump(target, args)) {
      guard block_id_to_index.get(target) is Some(target_idx) else { continue }
      let target_block = self.func.blocks[target_idx]
      let edge_slots : Set[Int] = Set([])
      for i, param in target_block.params {
        if i >= args.length() {
          break
        }
        guard args[i] is Virtual(arg_vreg) else { continue }
        if result.spill_slots.get(arg_vreg.id) is Some(src_slot) {
          edge_slots.add(src_slot) |> ignore
        }
        if result.spill_slots.get(param.id) is Some(dst_slot) {
          edge_slots.add(dst_slot) |> ignore
        }
      }
      if edge_slots.length() <= 1 {
        continue
      }
      let slots : Array[Int] = []
      for slot in edge_slots {
        slots.push(slot)
      }
      for i in 0..<slots.length() {
        for j in (i + 1)..<slots.length() {
          no_share_edges.push({ lhs: slots[i], rhs: slots[j] })
        }
      }
    }
  }

  // 3) Assign spillsets to a compact set of physical spill slots.
  let compaction = @backtracking.compact_backtracking_spill_slots(
    spillsets,
    no_share_edges,
    reserve_abi_spill_slot,
    fn(a, b) { spans_overlap(a, b, self.ranges.block_order) },
    fn(a, b) { a.compare_with_order(b, self.ranges.block_order) },
  )
  let slot_remap : Map[Int, Int] = {}
  for remap in compaction.remaps {
    slot_remap.set(remap.old_slot, remap.new_slot)
  }

  // 4) Rewrite all spill-slot references (spill map + constraint edits).
  for vreg_id, old_slot in result.spill_slots {
    if slot_remap.get(old_slot) is Some(new_slot) {
      result.spill_slots.set(vreg_id, new_slot)
    }
  }
  for entry in result.inst_edits {
    let (_, _, edits) = entry
    for i in 0..<edits.before.length() {
      let mv = edits.before[i]
      let from = match mv.from {
        Spill(s) =>
          match slot_remap.get(s) {
            Some(ns) => Loc::Spill(ns)
            None => mv.from
          }
        _ => mv.from
      }
      let to = match mv.to {
        Spill(s) =>
          match slot_remap.get(s) {
            Some(ns) => Loc::Spill(ns)
            None => mv.to
          }
        _ => mv.to
      }
      edits.before[i] = { from, to, class: mv.class }
    }
    for i in 0..<edits.after.length() {
      let mv = edits.after[i]
      let from = match mv.from {
        Spill(s) =>
          match slot_remap.get(s) {
            Some(ns) => Loc::Spill(ns)
            None => mv.from
          }
        _ => mv.from
      }
      let to = match mv.to {
        Spill(s) =>
          match slot_remap.get(s) {
            Some(ns) => Loc::Spill(ns)
            None => mv.to
          }
        _ => mv.to
      }
      edits.after[i] = { from, to, class: mv.class }
    }
  }

  // 5) Return total spill-slot count.
  compaction.total_slots
}

///|
/// Build bundles with merging from Move instructions and block arguments
pub fn build_bundles_with_merging(
  func : @machv.Function,
  ranges : LiveRangeSet,
) -> BundleSet {
  let perf_on = perf_enabled()
  let n = ranges.length()
  let num_blocks = func.blocks.length()
  let block_idx_by_order : Array[Int] = Array::make(num_blocks, 0)
  for block_idx in 0..<num_blocks {
    block_idx_by_order[ranges.block_order[block_idx]] = block_idx
  }
  let block_point_base : Array[Int] = Array::make(num_blocks, 0)
  let mut point_cursor = 0
  for ord in 0..<num_blocks {
    block_point_base[ord] = point_cursor
    let block_idx = block_idx_by_order[ord]
    let block_len = func.blocks[block_idx].insts.length()
    point_cursor = point_cursor + (block_len + 2) * 2
  }
  fn point_order(
    point : ProgPoint,
    block_order : FixedArray[Int],
    block_point_base : Array[Int],
  ) -> Int {
    let block_ord = block_order[point.block]
    let pos_ord = match point.pos {
      Before => 0
      After => 1
    }
    block_point_base[block_ord] + (point.inst + 1) * 2 + pos_ord
  }
  fn same_fixed_bank(a : @abi.PReg, b : @abi.PReg) -> Bool {
    match (a.class, b.class) {
      (Int, Int) => true
      (Float32 | Float64 | Vector, Float32 | Float64 | Vector) => true
      _ => false
    }
  }

  fn range_fixed_reg_conflict(range : LiveRange) -> (@abi.PReg?, Bool) {
    let mut fixed : @abi.PReg? = None
    for use_pos in range.uses {
      if use_pos.constraint is FixedReg(preg) {
        match fixed {
          None => fixed = Some(preg)
          Some(existing) =>
            if existing.index != preg.index || !same_fixed_bank(existing, preg) {
              return (None, true)
            }
        }
      }
    }
    (fixed, false)
  }

  fn range_has_fixed_def(range : LiveRange) -> Bool {
    for use_pos in range.uses {
      if use_pos.kind is Def && use_pos.constraint is FixedReg(_) {
        return true
      }
    }
    false
  }

  fn make_merge_span(
    span : ProgPointRange,
    block_order : FixedArray[Int],
    block_point_base : Array[Int],
  ) -> MergeSpan {
    let start_ord = point_order(span.start, block_order, block_point_base)
    let start_before_ord = point_order(
      { block: span.start.block, inst: span.start.inst, pos: Before },
      block_order,
      block_point_base,
    )
    {
      span,
      start_ord,
      start_before_ord,
      end_ord: point_order(span.end, block_order, block_point_base),
    }
  }

  let tick_init_metadata = if perf_on { Some(perf_tick_now()) } else { None }
  let projected : Array[
    @backtracking.BundleMergeRange[@abi.RegClass, @abi.PReg, ProgPointRange],
  ] = []
  for i in 0..<n {
    let range = ranges.get(i)
    let (fixed_reg, fixed_conflict) = range_fixed_reg_conflict(range)
    let spans : Array[MergeSpan] = []
    for span in range.ranges {
      spans.push(make_merge_span(span, ranges.block_order, block_point_base))
    }
    projected.push({
      id: i,
      class: range.vreg.class,
      spans,
      fixed_reg,
      has_fixed_conflict: fixed_conflict,
      has_fixed_def: range_has_fixed_def(range),
    })
  }
  if tick_init_metadata is Some(tick) {
    perf_record_regalloc_phase_us(
      "phase_bundle_merge_init",
      perf_elapsed_us(tick),
    )
  }

  let tick_merge_blockargs = if perf_on { Some(perf_tick_now()) } else { None }
  let merge_edges : Array[@backtracking.BundleMergeEdge] = []
  for pair in ranges.blockparam_out_pairs {
    let (param_idx, arg_idx) = pair
    if arg_idx != param_idx {
      merge_edges.push({ target: param_idx, source: arg_idx })
    }
  }
  let plan = @backtracking.plan_bundle_merges(
    projected, merge_edges, reg_class_compatible, same_fixed_bank,
  )
  if tick_merge_blockargs is Some(tick) {
    perf_record_regalloc_phase_us(
      "phase_bundle_merge_blockargs",
      perf_elapsed_us(tick),
    )
  }

  let tick_finalize = if perf_on { Some(perf_tick_now()) } else { None }
  let result = BundleSet::BundleSet()
  for bundle_id in 0..<plan.bundle_roots.length() {
    let created = Bundle::Bundle(
      result.bundles.length(),
      plan.bundle_classes[bundle_id],
    )
    result.add_bundle(created)
  }
  for range_idx in 0..<n {
    let bundle_id = plan.range_to_bundle[range_idx]
    let bundle = result.get(bundle_id)
    bundle.add_range(range_idx)
    ranges.get(range_idx).bundle_id = bundle.id
  }
  for bundle_id in 0..<result.bundles.length() {
    let bundle = result.get(bundle_id)
    let merged_ranges : Array[ProgPointRange] = []
    for span in plan.bundle_ranges[bundle_id] {
      merged_ranges.push(span)
    }
    bundle.merged_ranges = Some(merged_ranges)
  }
  if tick_finalize is Some(tick) {
    perf_record_regalloc_phase_us(
      "phase_bundle_merge_finalize",
      perf_elapsed_us(tick),
    )
  }
  result
}

///|
/// Pre-assign function parameters to ABI registers
/// This must be done before allocation to respect calling convention
fn BacktrackingAllocator::force_spill_bundle(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Unit {
  let spill_bundle = self.bundles.get_or_create_spill_bundle(bundle)
  let slot = spill_bundle.slot
  bundle.allocation = Spill(slot)
  for range_id in bundle.range_ids {
    let range = self.ranges.get(range_id)
    range.allocation = Spill(slot)
  }
}

///|
fn BacktrackingAllocator::preassign_params(
  self : BacktrackingAllocator,
  embedding_abi : @abi.EmbeddingABI,
  strict_precolor : Bool,
) -> Unit {
  let call_conv_layout = embedding_abi.call_conv
  let context_arg_preg = call_conv_layout.context_arg
  let pinned_context_preg = embedding_abi.reg_roles.context.unwrap_or(
    context_arg_preg,
  )
  let user_arg_gprs = call_conv_layout.user_arg_gprs
  let arg_fprs = call_conv_layout.arg_fprs
  let mut int_idx = 0
  let mut float_idx = 0
  for param in self.func.params {
    // Determine which ABI register this param comes in
    let (preg_opt, is_int) : (@abi.PReg?, Bool) = match param.class {
      Int =>
        if int_idx == 0 {
          // First integer argument is the embedding context in this call ABI.
          (Some(context_arg_preg), true)
        } else if int_idx - 1 < user_arg_gprs.length() {
          (Some(user_arg_gprs[int_idx - 1]), true)
        } else {
          (None, true) // Stack param
        }
      Float32 | Float64 | Vector =>
        if float_idx < arg_fprs.length() {
          let base = arg_fprs[float_idx]
          (Some({ index: base.index, class: param.class }), false)
        } else {
          (None, false) // Stack param
        }
    }

    // Update counters
    if is_int {
      int_idx = int_idx + 1
    } else {
      float_idx = float_idx + 1
    }

    // Skip stack params (handled by normal allocation).
    guard preg_opt is Some(preg) else { continue }
    let is_context_param = param.class is Int &&
      preg.index == context_arg_preg.index &&
      preg.class == context_arg_preg.class

    // Find the LiveRange for this param and get its bundle
    let range = self.ranges.get_by_vreg(param.id)
    if range is Some(lr) && lr.bundle_id >= 0 {
      let bundle = self.bundles.bundles[lr.bundle_id]
      // The same bundle may be reached through multiple params after coalescing.
      // Keep the first pre-assignment decision.
      if bundle.allocation is Reg(_) || bundle.allocation is Spill(_) {
        continue
      }
      // If the param's bundle crosses a call (even if the param itself doesn't),
      // avoid pre-assigning caller-saved ABI arg registers. Let the allocator
      // choose a safe location from full liveness/call-clobber information.
      if bundle.crosses_call(self.ranges) {
        if is_context_param {
          self.record_allocation(bundle, pinned_context_preg)
          bundle.is_pinned = true
          continue
        }

        // Cranelift-like bias for call-crossing values: if a call-crossing
        // parameter can be kept in a callee-saved register up front, prefer
        // that over letting it fall back to caller-saved arg regs and frequent
        // spill/reload traffic around calls.
        //
        // This remains opportunistic: only pre-assign when the register is
        // currently conflict-free; otherwise keep the bundle unassigned and let
        // normal allocation decide.
        let mut assigned = false
        match param.class {
          Int =>
            for callee_preg in self.callee_saved_int {
              if self.is_reg_free(callee_preg, bundle) {
                self.record_allocation(bundle, callee_preg)
                assigned = true
                break
              }
            }
          Float32 | Float64 =>
            for callee_preg in self.callee_saved_float {
              if self.is_reg_free(callee_preg, bundle) {
                self.record_allocation(bundle, callee_preg)
                assigned = true
                break
              }
            }
          Vector => ()
        }
        if !assigned {
          // Give split pieces a callee-saved preference when possible.
          let hint = match param.class {
            Int =>
              if self.callee_saved_int.length() > 0 {
                Some(self.callee_saved_int[0])
              } else {
                None
              }
            Float32 | Float64 =>
              if self.callee_saved_float.length() > 0 {
                Some(self.callee_saved_float[0])
              } else {
                None
              }
            Vector => None
          }
          if hint is Some(hint_preg) {
            self.spillsets.record_hint(bundle.spillset_id, hint_preg)
          }
        }
        continue
      }

      // Normal case:
      // - strict mode: pin param bundle to incoming ABI register.
      // - relaxed mode: keep the embedding context pinned, but treat other
      //   params as hints only.
      if strict_precolor || is_context_param {
        self.record_allocation(bundle, preg)
        // Keep the embedding context pinned. For strict precoloring, only pin
        // params that do not cross calls; call-crossing values must remain
        // movable so the allocator can satisfy call-clobber constraints.
        if is_context_param ||
          (strict_precolor && !bundle.crosses_call(self.ranges)) {
          bundle.is_pinned = true
        }
      } else {
        self.spillsets.record_hint(bundle.spillset_id, preg)
      }
    }
  }
}

///|
/// Project MachV liveness/bundles into `regalloc` backtracking APIs and
/// materialize the generic allocation decisions as a MachV `RegAllocResult`.
fn allocate_backtracking(
  func : @machv.Function,
  liveness : LivenessResult,
  int_regs : Array[@abi.PReg],
  float_regs : Array[@abi.PReg],
  vector_regs : Array[@abi.PReg],
  callee_saved_int : Array[@abi.PReg],
  callee_saved_float : Array[@abi.PReg],
  embedding_abi : @abi.EmbeddingABI,
  param_precolor_strict? : Bool = true,
  algorithm? : RegallocAlgorithm = Backtracking,
) -> RegAllocResult {
  let perf_on = perf_enabled()

  // Phase 2: Build LiveRanges
  let tick_live_ranges = if perf_on { Some(perf_tick_now()) } else { None }
  let ranges = build_live_ranges(func, liveness)
  if tick_live_ranges is Some(tick) {
    perf_record_regalloc_phase_us("phase_live_ranges", perf_elapsed_us(tick))
  }

  // Phase 3: Build Bundles with merging
  let tick_bundles = if perf_on { Some(perf_tick_now()) } else { None }
  let bundles = build_bundles_with_merging(func, ranges)
  if tick_bundles is Some(tick) {
    perf_record_regalloc_phase_us("phase_bundle_merge", perf_elapsed_us(tick))
  }

  // Phase 4: Allocate
  let tick_alloc_new = if perf_on { Some(perf_tick_now()) } else { None }
  let allocator = BacktrackingAllocator::BacktrackingAllocator(
    func,
    ranges,
    bundles,
    int_regs,
    float_regs,
    vector_regs,
    callee_saved_int,
    callee_saved_float,
    algorithm~,
  )
  if tick_alloc_new is Some(tick) {
    perf_record_regalloc_phase_us("phase_allocator_new", perf_elapsed_us(tick))
  }

  // Pre-assign function parameters to ABI registers (before main allocation)
  let tick_preassign = if perf_on { Some(perf_tick_now()) } else { None }
  allocator.preassign_params(embedding_abi, param_precolor_strict)
  if tick_preassign is Some(tick) {
    perf_record_regalloc_phase_us(
      "phase_preassign_params",
      perf_elapsed_us(tick),
    )
  }
  let tick_allocate = if perf_on { Some(perf_tick_now()) } else { None }
  allocator.allocate()
  if tick_allocate is Some(tick) {
    perf_record_regalloc_phase_us("phase_allocate_main", perf_elapsed_us(tick))
  }

  // Generate result
  let tick_result = if perf_on { Some(perf_tick_now()) } else { None }
  let result = allocator.generate_result()
  if tick_result is Some(tick) {
    perf_record_regalloc_phase_us(
      "phase_generate_result",
      perf_elapsed_us(tick),
    )
  }
  result
}
