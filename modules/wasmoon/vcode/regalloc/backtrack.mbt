// Ion-Style Backtracking Register Allocator
// Main allocator implementation with bundle merging, eviction, and splitting.

///|
fn backtrack_core_reg_class(class : @abi.RegClass) -> @core_regalloc.RegClass {
  match class {
    Int => Int
    Float32 | Float64 => Float
    Vector => Vector
  }
}

///|
fn backtrack_core_preg(preg : @abi.PReg) -> @core_regalloc.PhysicalReg {
  { id: preg.index, class: backtrack_core_reg_class(preg.class) }
}

///|
fn backtrack_core_pregs(
  regs : Array[@abi.PReg],
) -> Array[@core_regalloc.PhysicalReg] {
  let out : Array[@core_regalloc.PhysicalReg] = []
  for preg in regs {
    out.push(backtrack_core_preg(preg))
  }
  out
}

///|
fn backtrack_preg_from_probe(
  preg : @core_regalloc.PhysicalReg,
  fallback_class : @abi.RegClass,
  available_regs : Array[@abi.PReg],
  caller_saved_regs : Array[@abi.PReg],
  callee_saved_regs : Array[@abi.PReg],
) -> @abi.PReg {
  fn find_in(regs : Array[@abi.PReg], id : Int) -> @abi.PReg? {
    for candidate in regs {
      if candidate.index == id {
        return Some(candidate)
      }
    }
    None
  }

  match find_in(available_regs, preg.id) {
    Some(found) => found
    None =>
      match find_in(caller_saved_regs, preg.id) {
        Some(found) => found
        None =>
          match find_in(callee_saved_regs, preg.id) {
            Some(found) => found
            None => { index: preg.id, class: fallback_class }
          }
      }
  }
}

///|
fn backtrack_core_point(point : ProgPoint) -> @core_regalloc.ProgramPoint {
  let pos = match point.pos {
    Before => 0
    After => 1
  }
  @core_regalloc.ProgramPoint::new(point.block, point.inst * 2 + pos)
}

///|
fn backtrack_old_point(point : @core_regalloc.ProgramPoint) -> ProgPoint {
  {
    block: point.block,
    inst: point.inst / 2,
    pos: if point.inst % 2 == 0 {
      Before
    } else {
      After
    },
  }
}

///|
fn backtrack_old_range(range : @core_regalloc.ProgramRange) -> ProgPointRange {
  ProgPointRange::new(
    backtrack_old_point(range.start),
    backtrack_old_point(range.end),
  )
}

///|
fn backtrack_core_block_order(block_order : FixedArray[Int]) -> Array[Int] {
  let out : Array[Int] = []
  for i in 0..<block_order.length() {
    out.push(block_order[i])
  }
  out
}

///|
/// Register allocation algorithm policy.
///
/// - Backtracking: Ion-style backtracking + eviction/splitting (better codegen).
/// - SinglePass: no eviction/backtracking, spills earlier (faster compile).
pub(all) enum RegallocAlgorithm {
  Backtracking
  SinglePass
}

///|
/// A span with precomputed total-order keys for faster overlap tests.
priv struct OrderedSpan {
  start : ProgPoint
  start_ord : Int
  end_ord : Int
}

///|
/// The backtracking register allocator
struct BacktrackingAllocator {
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

  // Priority queue of bundles to process.
  mut queue : @core_regalloc.PriorityWorkQueue
  queue_hints : Array[@abi.PReg?]
  queue_in_heap : Array[Bool]

  // Cranelift-style spillset hint: remember last successful preg for an
  // "original" bundle (spillset), and prefer it for split pieces.
  spillset_hints : Array[@abi.PReg?]
  // Track split count per original spillset (regalloc2 MAX_SPLITS_PER_SPILLSET).
  spillset_split_counts : Array[Int]
  max_splits_per_spillset : Int
  // Cache fixed-constraint-derived hints per bundle to avoid rescanning
  // all bundle uses on every queue pop.
  bundle_hint_cache : Array[@abi.PReg?]
  bundle_hint_ready : Array[Bool]

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
  func : VCodeFunction
  bundle_attempts : Array[Int]
  scratch_conflicts : Array[Int]
  scratch_best_conflicts : Array[Int]
}

///|
/// Heap push into the allocator queue.
fn BacktrackingAllocator::queue_push(
  self : BacktrackingAllocator,
  bundle_id : Int,
  prio : Int,
  hint_preg : @abi.PReg?,
) -> Unit {
  if bundle_id >= 0 &&
    bundle_id < self.queue_in_heap.length() &&
    self.queue_in_heap[bundle_id] {
    return
  }
  if bundle_id >= 0 && bundle_id < self.queue_hints.length() {
    self.queue_hints[bundle_id] = hint_preg
  }
  self.queue.push(bundle_id, prio)
  if bundle_id >= 0 && bundle_id < self.queue_in_heap.length() {
    self.queue_in_heap[bundle_id] = true
  }
}

///|
/// Heap pop-max from the allocator queue.
fn BacktrackingAllocator::queue_pop(
  self : BacktrackingAllocator,
) -> @core_regalloc.PriorityWorkItem? {
  let top = self.queue.pop()
  match top {
    None => None
    Some(item) => {
      if item.item_id >= 0 && item.item_id < self.queue_in_heap.length() {
        self.queue_in_heap[item.item_id] = false
      }
      Some(item)
    }
  }
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
  let table : Array[Array[(Int, OrderedSpan)]] = []
  for _ in 0..<cap {
    table.push([])
  }
  table
}

///|
fn make_bool_table(cap : Int) -> Array[Bool] {
  let table : Array[Bool] = []
  for _ in 0..<cap {
    table.push(false)
  }
  table
}

///|
pub fn BacktrackingAllocator::new(
  func : VCodeFunction,
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
  let enable_backtracking = algorithm is Backtracking
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
    queue: @core_regalloc.PriorityWorkQueue::new(),
    queue_hints: Array::make(bundles.length(), None),
    queue_in_heap: Array::make(bundles.length(), false),
    spillset_hints: Array::make(bundles.length(), None),
    spillset_split_counts: Array::make(bundles.length(), 0),
    max_splits_per_spillset: 2,
    bundle_hint_cache: Array::make(bundles.length(), None),
    bundle_hint_ready: Array::make(bundles.length(), false),
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
    scratch_conflicts: [],
    scratch_best_conflicts: [],
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

  fn from_core_preg(preg : @core_regalloc.PhysicalReg) -> @abi.PReg {
    { index: preg.id, class: bundle.reg_class }
  }

  let available : Array[@core_regalloc.PhysicalReg] = []
  for preg in avail_regs {
    available.push(backtrack_core_preg(preg))
  }

  let fixed : Array[@core_regalloc.PhysicalReg] = []
  for range_id in bundle.range_ids {
    let range = self.ranges.get(range_id)
    for use_pos in range.uses {
      if use_pos.constraint is FixedReg(preg) && preg.class == bundle.reg_class {
        fixed.push(backtrack_core_preg(preg))
      }
    }
  }
  @core_regalloc.choose_fixed_reg_hint(available, fixed).map(from_core_preg)
}

///|
fn BacktrackingAllocator::constraint_hint_preg_cached(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> @abi.PReg? {
  if bundle.id >= 0 &&
    bundle.id < self.bundle_hint_ready.length() &&
    self.bundle_hint_ready[bundle.id] {
    return self.bundle_hint_cache[bundle.id]
  }
  let hint = self.constraint_hint_preg(bundle)
  if bundle.id >= 0 && bundle.id < self.bundle_hint_ready.length() {
    self.bundle_hint_ready[bundle.id] = true
    self.bundle_hint_cache[bundle.id] = hint
  }
  hint
}

///|
/// Initialize the priority queue with all bundles
fn BacktrackingAllocator::init_queue(self : BacktrackingAllocator) -> Unit {
  self.queue = @core_regalloc.PriorityWorkQueue::new()
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
/// Find first occupied index whose span.end is strictly after `point`.
/// Occupied spans for one preg are non-overlapping and sorted by start, so end
/// order is also monotonic.
fn BacktrackingAllocator::occupied_lower_bound_by_end(
  self : BacktrackingAllocator,
  occupied : Array[(Int, OrderedSpan)],
  point_ord : Int,
) -> Int {
  ignore(self)
  let mut lo = 0
  let mut hi = occupied.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let end_ord = occupied[mid].1.end_ord
    if end_ord <= point_ord {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
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
  let mut i = 0
  let mut j = self.occupied_lower_bound_by_end(occupied, spans[0].start_ord)
  while i < spans.length() && j < occupied.length() {
    let span = spans[i]
    let occ = occupied[j].1
    if span.end_ord <= occ.start_ord {
      i = i + 1
      continue
    }
    if occ.end_ord <= span.start_ord {
      j = j + 1
      continue
    }
    return true
  }
  false
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
  if bundle.crosses_call(self.ranges) {
    match bundle.reg_class {
      Int => self.callee_saved_int
      Float32 | Float64 => self.callee_saved_float
      // V8-V15 preservation is only guaranteed for the low 64 bits by AAPCS64.
      // Vector values that cross calls are handled by forced spilling earlier.
      Vector => []
    }
  } else {
    match bundle.reg_class {
      Int => self.int_regs
      Float32 | Float64 => self.float_regs
      Vector => self.vector_regs
    }
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
fn BacktrackingAllocator::probe_order_for_bundle(
  self : BacktrackingAllocator,
  bundle : Bundle,
  available_regs : Array[@abi.PReg],
  scan_limit : Int,
  offset : Int,
  skip_reg : @abi.PReg?,
) -> Array[@abi.PReg] {
  let (caller_saved, callee_saved, prefer) = match bundle.reg_class {
    Int =>
      (
        self.int_caller_saved,
        self.callee_saved_int,
        self.enable_backtracking && !bundle.crosses_call(self.ranges),
      )
    Float32 | Float64 =>
      (
        self.float_caller_saved,
        self.callee_saved_float,
        self.enable_backtracking && !bundle.crosses_call(self.ranges),
      )
    Vector => ([], [], false)
  }
  let core_order = @core_regalloc.plan_register_probe_order(
    backtrack_core_pregs(available_regs),
    backtrack_core_pregs(caller_saved),
    backtrack_core_pregs(callee_saved),
    prefer,
    scan_limit,
    offset,
    skip_reg.map(backtrack_core_preg),
  )
  let out : Array[@abi.PReg] = []
  for core_preg in core_order {
    out.push(
      backtrack_preg_from_probe(
        core_preg,
        bundle.reg_class,
        available_regs,
        caller_saved,
        callee_saved,
      ),
    )
  }
  out
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
  let spillset_id = bundle.spillset_id
  if spillset_id >= 0 && spillset_id < self.spillset_hints.length() {
    self.spillset_hints[spillset_id] = Some(preg)
  }
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
  let n = avail_regs.length()
  if n == 0 {
    return None
  }
  let spans = self.bundle_sorted_spans(bundle)

  // Probe hint first if present and available.
  if hint_preg is Some(hint) {
    for preg in avail_regs {
      if preg.class == hint.class && preg.index == hint.index {
        if !self.has_conflict_on_preg_with_spans(spans, preg) {
          return Some(preg)
        }
        break
      }
    }
  }

  // Try each available register (Cranelift-like offset scan to distribute contention).
  // Use cached sorted bundle spans to derive deterministic probe offset.
  // This avoids repeated per-attempt scans over bundle ranges.
  let start_inst = if !spans.is_empty() { spans[0].start.inst } else { 0 }
  let scan_limit = if self.split_probe_limit < n {
    self.split_probe_limit
  } else {
    n
  }
  let raw_phase_offset = bundle.id + start_inst
  for
    preg in self.probe_order_for_bundle(
      bundle, avail_regs, scan_limit, raw_phase_offset, hint_preg,
    ) {
    if !self.has_conflict_on_preg_with_spans(spans, preg) {
      return Some(preg)
    }
  }
  None
}

///|
fn BacktrackingAllocator::scan_conflicts_with_cutoff(
  self : BacktrackingAllocator,
  bundle : Bundle,
  preg : @abi.PReg,
  spans : Array[OrderedSpan],
  max_allowable_cost : Int?,
  conflicts : Array[Int],
) -> (Int, ProgPoint?, Bool) {
  conflicts.clear()
  let allocs = self.get_reg_allocs(preg.class)
  if preg.index < 0 || preg.index >= allocs.length() {
    return (0, None, false)
  }
  let occupied = allocs[preg.index]
  if occupied.is_empty() || spans.is_empty() {
    return (0, None, false)
  }

  fn core_point(point : ProgPoint) -> @core_regalloc.ProgramPoint {
    let pos = match point.pos {
      Before => 0
      After => 1
    }
    @core_regalloc.ProgramPoint::new(point.block, point.inst * 2 + pos)
  }

  fn core_span(span : OrderedSpan) -> @core_regalloc.OrderedProgramSpan {
    {
      start: core_point(span.start),
      start_ord: span.start_ord,
      end_ord: span.end_ord,
    }
  }

  fn old_point(point : @core_regalloc.ProgramPoint) -> ProgPoint {
    let pos = if point.inst % 2 == 0 { Before } else { After }
    { block: point.block, inst: point.inst / 2, pos }
  }

  let core_spans : Array[@core_regalloc.OrderedProgramSpan] = []
  for span in spans {
    core_spans.push(core_span(span))
  }
  let core_occupied : Array[@core_regalloc.OccupiedProgramSpan] = []
  for entry in occupied {
    let (owner_id, span) = entry
    if owner_id >= 0 && owner_id < self.bundles.length() {
      let other = self.bundles.get(owner_id)
      core_occupied.push({
        owner_id,
        span: core_span(span),
        owner_weight: other.spill_weight,
        owner_pinned: other.is_pinned,
      })
    } else {
      core_occupied.push({
        owner_id,
        span: core_span(span),
        owner_weight: bundle.spill_weight,
        owner_pinned: true,
      })
    }
  }
  let result = @core_regalloc.scan_conflicts_with_cutoff(
    core_spans,
    core_occupied,
    bundle.spill_weight,
    max_allowable_cost,
  )
  for id in result.conflict_ids {
    conflicts.push(id)
  }
  let first_conflict_point = result.first_conflict_point.map(old_point)
  (result.max_conflict_weight, first_conflict_point, result.rejected)
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
  let n = avail_regs.length()
  if n == 0 {
    return (None, None)
  }
  let spans = self.bundle_sorted_spans(bundle)
  let scan_limit = if self.split_probe_limit < n {
    self.split_probe_limit
  } else {
    n
  }
  let raw_phase_offset = bundle.id
  let mut best_preg : @abi.PReg? = None
  let mut best_conflict_cost : Int? = None
  let best_conflicts = self.scratch_best_conflicts
  let scratch_conflicts = self.scratch_conflicts
  best_conflicts.clear()
  scratch_conflicts.clear()
  let mut best_split_cost : Int? = None
  let mut best_split : (ProgPoint, @abi.PReg)? = None
  for
    preg in self.probe_order_for_bundle(
      bundle,
      avail_regs,
      scan_limit,
      raw_phase_offset,
      None,
    ) {
    // regalloc2-style high-cost cutoff:
    // when we already have a best candidate (evict/split), stop considering
    // higher-cost registers early.
    let cutoff = @core_regalloc.eviction_cutoff(
      best_conflict_cost, best_split_cost,
    )
    let (max_conflict_weight, first_conflict_point, rejected) = self.scan_conflicts_with_cutoff(
      bundle, preg, spans, cutoff, scratch_conflicts,
    )
    if rejected {
      continue
    }
    if scratch_conflicts.is_empty() {
      return (Some(preg), None)
    }
    if first_conflict_point is Some(point) {
      let best_split_point = match best_split {
        Some((existing_point, _)) => Some(backtrack_core_point(existing_point))
        None => None
      }
      if @core_regalloc.should_take_split_candidate(
          best_split_cost,
          best_split_point,
          max_conflict_weight,
          backtrack_core_point(point),
          backtrack_core_block_order(self.block_order),
        ) {
        best_split_cost = Some(max_conflict_weight)
        best_split = Some((point, preg))
      }
    }

    // Keep only legal eviction candidates.
    // Mirrors regalloc2's "lowest conflict cost" selection strategy:
    // - reject pinned / heavier-or-equal conflicts
    // - choose the candidate with minimum maximum conflict spill weight.
    if @core_regalloc.should_take_eviction_candidate(
        best_conflict_cost,
        best_preg.map(backtrack_core_preg),
        max_conflict_weight,
        backtrack_core_preg(preg),
        hint_preg.map(backtrack_core_preg),
      ) {
      best_preg = Some(preg)
      best_conflict_cost = Some(max_conflict_weight)
      best_conflicts.clear()
      for conflict_id in scratch_conflicts {
        best_conflicts.push(conflict_id)
      }
    }
  }
  if best_preg is Some(preg) {
    // Only evict when our spill weight strictly dominates the chosen conflict cost.
    if best_conflict_cost is Some(cost) && bundle.spill_weight > cost {
      for conflict_id in best_conflicts {
        let conflict = self.bundles.get(conflict_id)
        self.remove_allocation(conflict)
        self.queue_push(conflict_id, self.bundle_queue_prio(conflict), None)
      }
      return (Some(preg), None)
    }
  }
  best_conflicts.clear()
  scratch_conflicts.clear()
  (None, best_split)
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
  // regalloc2/Ion guards split explosion with MAX_SPLITS_PER_SPILLSET.
  // Once a spillset exceeds this cap, fall back to direct spilling.
  let spillset_id = bundle.spillset_id
  let split_count = if spillset_id >= 0 &&
    spillset_id < self.spillset_split_counts.length() {
    self.spillset_split_counts[spillset_id]
  } else {
    0
  }
  let split_ranges : Array[@core_regalloc.BundleSplitRange] = []
  for range_id in bundle.range_ids {
    let range = self.ranges.get(range_id)
    split_ranges.push({
      range_id,
      start: range.start(self.block_order).map(backtrack_core_point),
      end: range.end(self.block_order).map(backtrack_core_point),
    })
  }
  let split_plan = @core_regalloc.plan_bundle_split(
    split_ranges,
    split_opt.map(fn(pair) {
      let (point, _) = pair
      backtrack_core_point(point)
    }),
    backtrack_core_block_order(self.block_order),
    split_count,
    self.max_splits_per_spillset,
  )
  if split_opt is Some(_) &&
    spillset_id >= 0 &&
    spillset_id < self.spillset_split_counts.length() &&
    split_count < self.max_splits_per_spillset {
    self.spillset_split_counts[spillset_id] = split_count + 1
  }

  match split_plan {
    Split(before_ranges, after_ranges) => {
      let split_hint_reg = match split_opt {
        Some((_, hint)) => hint
        None => abort("regalloc split plan lost split hint")
      }
      let spill_bundle = self.bundles.get_or_create_spill_bundle(bundle)

      // Before bundle
      let before_bundle = Bundle::new(
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
      self.queue_hints.push(None)
      self.queue_in_heap.push(false)
      self.bundle_attempts.push(0)
      self.bundle_span_cache.push(None)
      self.bundle_hint_cache.push(None)
      self.bundle_hint_ready.push(false)
      spill_bundle.add_bundle(before_bundle.id)
      self.queue_push(
        before_bundle.id,
        self.bundle_queue_prio(before_bundle),
        Some(split_hint_reg),
      )

      // After bundle
      let after_bundle = Bundle::new(
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
      self.queue_hints.push(None)
      self.queue_in_heap.push(false)
      self.bundle_attempts.push(0)
      self.bundle_span_cache.push(None)
      self.bundle_hint_cache.push(None)
      self.bundle_hint_ready.push(false)
      spill_bundle.add_bundle(after_bundle.id)
      self.queue_push(
        after_bundle.id,
        self.bundle_queue_prio(after_bundle),
        Some(split_hint_reg),
      )

      // Mark original bundle as processed (it's been split)
      bundle.allocation = Spill(spill_bundle.slot)
    }
    Minimal => self.split_into_minimal_bundles(bundle, split_hint)
    SpillWhole => {
      // No conflict point found, just spill the entire bundle
      let spill_bundle = self.bundles.get_or_create_spill_bundle(bundle)
      let slot = spill_bundle.slot
      bundle.allocation = Spill(slot)
      for range_id in bundle.range_ids {
        let range = self.ranges.get(range_id)
        range.allocation = Spill(slot)
      }
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
  let new_bundle = Bundle::new(
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
  self.queue_hints.push(None)
  self.queue_in_heap.push(false)
  self.bundle_attempts.push(0)
  self.bundle_span_cache.push(None)
  self.bundle_hint_cache.push(None)
  self.bundle_hint_ready.push(false)
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
pub fn BacktrackingAllocator::allocate(self : BacktrackingAllocator) -> Unit {
  self.init_queue()

  let max_iterations = self.bundles.length() * 10 // Safety limit
  let mut iterations = 0
  while self.queue.length() > 0 && iterations < max_iterations {
    iterations += 1

    // Pop highest priority bundle
    let entry = match self.queue_pop() {
      Some(e) => e
      None => break
    }
    let bundle_id = entry.item_id
    let bundle = self.bundles.get(bundle_id)
    let queued_hint = if bundle_id >= 0 && bundle_id < self.queue_hints.length() {
      self.queue_hints[bundle_id]
    } else {
      None
    }
    if bundle_id >= 0 && bundle_id < self.queue_hints.length() {
      self.queue_hints[bundle_id] = None
    }
    let hint_preg = match queued_hint {
      Some(p) => Some(p)
      None => {
        let spillset_id = bundle.spillset_id
        if spillset_id >= 0 && spillset_id < self.spillset_hints.length() {
          self.spillset_hints[spillset_id]
        } else {
          None
        }
      }
    }
    let hint_preg = match hint_preg {
      Some(p) => Some(p)
      None =>
        if self.enable_backtracking {
          self.constraint_hint_preg_cached(bundle)
        } else {
          None
        }
    }

    // Skip if already allocated
    if bundle.allocation is Reg(_) || bundle.allocation is Spill(_) {
      continue
    }
    if bundle_id >= 0 && bundle_id < self.bundle_attempts.length() {
      self.bundle_attempts[bundle_id] = self.bundle_attempts[bundle_id] + 1
      if self.bundle_attempts[bundle_id] > self.bundle_retry_limit &&
        !bundle.is_pinned &&
        !bundle.has_fixed_constraint(self.ranges) {
        self.force_spill_bundle(bundle)
        continue
      }
    }

    // Vector values live across calls must spill.
    if bundle.reg_class is Vector && bundle.crosses_call(self.ranges) {
      self.force_spill_bundle(bundle)
      continue
    }

    if self.enable_backtracking {
      // Cranelift/regalloc2-like single register scan: free-reg allocation and
      // eviction candidate selection share one conflict walk.
      let (alloc_preg, split_opt) = self.try_evict(bundle, hint_preg)
      if alloc_preg is Some(preg) {
        self.record_allocation(bundle, preg)
        continue
      }
      self.split_bundle(bundle, split_opt)
      continue
    } else {
      // Non-backtracking fallback keeps simple first-fit behavior.
      if self.try_allocate(bundle, hint_preg) is Some(preg) {
        self.record_allocation(bundle, preg)
        continue
      }
      if !bundle.is_pinned && !bundle.has_fixed_constraint(self.ranges) {
        self.force_spill_bundle(bundle)
        continue
      }
    }

    // Split (spill) the bundle
    self.split_bundle(bundle, None)
  }
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
/// Generate allocation result compatible with existing code
pub fn BacktrackingAllocator::generate_result(
  self : BacktrackingAllocator,
) -> RegAllocResult {
  // Generate any needed moves for split bundles
  let _moves = self.generate_moves()
  let result : RegAllocResult = {
    assignments: {},
    spill_slots: {},
    num_spill_slots: self.bundles.next_spill_slot,
    inst_edits: [],
  }
  let max_vreg_id = self.func.next_vreg_id
  let assignment_dense : Array[@abi.PReg?] = Array::make(max_vreg_id, None)
  let spill_slot_dense : Array[Int] = Array::make(max_vreg_id, -1)

  // Collect assignments from LiveRanges
  for i in 0..<self.ranges.length() {
    let range = self.ranges.get(i)
    match range.allocation {
      Reg(preg) => {
        // Ensure the preg class matches the vreg class
        // This is important for float registers where the pool uses Float64
        // but the vreg might be Float32
        let corrected_preg : @abi.PReg = {
          index: preg.index,
          class: range.vreg.class,
        }
        result.assignments.set(range.vreg.id, corrected_preg)
        if range.vreg.id >= 0 && range.vreg.id < max_vreg_id {
          assignment_dense[range.vreg.id] = Some(corrected_preg)
        }
      }
      Spill(slot) => {
        result.spill_slots.set(range.vreg.id, slot)
        if range.vreg.id >= 0 && range.vreg.id < max_vreg_id {
          spill_slot_dense[range.vreg.id] = slot
        }
      }
      Unallocated => () // Should not happen after allocation
    }
  }

  // Generate moves for FixedReg constraints
  // When a vreg is used/defined with a FixedReg constraint, we need to
  // insert moves if the vreg is allocated to a different register
  for block_idx, block in self.func.blocks {
    for inst_idx, inst in block.insts {
      // Skip if no constraints
      if inst.use_constraints.is_empty() && inst.def_constraints.is_empty() {
        continue
      }
      let edits = InstEdits::new()

      // Process use constraints (moves before the instruction)
      for i, constraint in inst.use_constraints {
        if constraint is FixedReg(required_preg) {
          let use_reg = inst.uses[i]
          if use_reg is Virtual(vreg) {
            // Check if already allocated to the required register
            let assigned_opt = if vreg.id >= 0 && vreg.id < max_vreg_id {
              assignment_dense[vreg.id]
            } else {
              result.assignments.get(vreg.id)
            }
            let spill_slot = if vreg.id >= 0 && vreg.id < max_vreg_id {
              spill_slot_dense[vreg.id]
            } else {
              match result.spill_slots.get(vreg.id) {
                Some(slot) => slot
                None => -1
              }
            }
            if assigned_opt is Some(assigned_preg) {
              if assigned_preg.index != required_preg.index {
                // Need to move from assigned to required
                edits.before.push({
                  from: Reg(assigned_preg),
                  to: Reg(required_preg),
                  class: vreg.class,
                })
              }
            } else if spill_slot >= 0 {
              // Spilled: need to reload to the required register
              edits.before.push({
                from: Spill(spill_slot),
                to: Reg(required_preg),
                class: vreg.class,
              })
            }
          } else if use_reg is Physical(preg) {
            if preg.index != required_preg.index {
              edits.before.push({
                from: Reg(preg),
                to: Reg(required_preg),
                class: preg.class,
              })
            }
          }
        }
      }

      // Process def constraints (moves after the instruction)
      for i, constraint in inst.def_constraints {
        if constraint is FixedReg(required_preg) {
          let def = inst.defs[i]
          if def.reg is Virtual(vreg) {
            // Check if already allocated to the required register
            let assigned_opt = if vreg.id >= 0 && vreg.id < max_vreg_id {
              assignment_dense[vreg.id]
            } else {
              result.assignments.get(vreg.id)
            }
            let spill_slot = if vreg.id >= 0 && vreg.id < max_vreg_id {
              spill_slot_dense[vreg.id]
            } else {
              match result.spill_slots.get(vreg.id) {
                Some(slot) => slot
                None => -1
              }
            }
            if assigned_opt is Some(assigned_preg) {
              if assigned_preg.index != required_preg.index {
                // Need to move from required to assigned
                // (the instruction produces in required_preg, we need to move to assigned)
                edits.after.push({
                  from: Reg(required_preg),
                  to: Reg(assigned_preg),
                  class: vreg.class,
                })
              }
            } else if spill_slot >= 0 {
              // Spilled: need to store from required register to spill slot
              edits.after.push({
                from: Reg(required_preg),
                to: Spill(spill_slot),
                class: vreg.class,
              })
            }
          }
        }
      }

      // Store edits if any
      if !edits.before.is_empty() || !edits.after.is_empty() {
        result.inst_edits.push((block_idx, inst_idx, edits))
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
  // (see regalloc2 doc/ION.md), but adapted to Wasmoon’s existing BundleSet.
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
  fn core_class(cls : @abi.RegClass) -> @core_regalloc.RegClass {
    match cls {
      Int => Int
      Float32 | Float64 => Float
      Vector => Vector
    }
  }

  fn core_point(point : ProgPoint) -> @core_regalloc.ProgramPoint {
    let pos = match point.pos {
      Before => 0
      After => 1
    }
    @core_regalloc.ProgramPoint::new(point.block, point.inst * 2 + pos)
  }

  fn core_range(span : ProgPointRange) -> @core_regalloc.ProgramRange {
    @core_regalloc.ProgramRange::new(
      core_point(span.start),
      core_point(span.end),
    )
  }

  fn core_block_order(block_order : FixedArray[Int]) -> Array[Int] {
    let out : Array[Int] = []
    for i in 0..<block_order.length() {
      out.push(block_order[i])
    }
    out
  }

  fn remap_lookup(
    remaps : Array[@core_regalloc.SpillSlotRemap],
    old_slot : Int,
  ) -> Int? {
    for remap in remaps {
      if remap.old_slot == old_slot {
        return Some(remap.new_slot)
      }
    }
    None
  }

  // 1) Build spillsets keyed by the old spill-slot id.
  let spillsets_by_slot : Map[Int, @core_regalloc.CompactSpillSet] = {}
  for vreg_id, old_slot in result.spill_slots {
    let range = match self.ranges.get_by_vreg(vreg_id) {
      Some(r) => r
      None => abort("missing LiveRange for spilled vreg \{vreg_id}")
    }
    let info = match spillsets_by_slot.get(old_slot) {
      Some(existing) => existing
      None => {
        let created : @core_regalloc.CompactSpillSet = {
          old_slot,
          class: core_class(range.vreg.class),
          ranges: [],
        }
        spillsets_by_slot.set(old_slot, created)
        created
      }
    }
    // Sanity: a spill slot should not mix register classes.
    if info.class != core_class(range.vreg.class) {
      abort(
        "spill slot \{old_slot} mixes classes while compacting \{range.vreg.class}",
      )
    }
    for span in range.ranges {
      info.ranges.push(core_range(span))
    }
  }
  if spillsets_by_slot.is_empty() {
    return 0
  }

  let spillsets : Array[@core_regalloc.CompactSpillSet] = []
  for _, info in spillsets_by_slot {
    spillsets.push(info)
  }

  // 2) Build anti-coalesce constraints for block-arg edge copies.
  //
  // Any spilled values participating in the same edge-parallel-copy must keep
  // distinct spill slots after compaction. Otherwise, compaction can collapse
  // logically distinct values onto one stack location at the jump boundary and
  // break SSA block-arg semantics.
  let no_share_edges : Array[@core_regalloc.SpillSlotNoShareEdge] = []
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

  let compaction = @core_regalloc.compact_spill_slots(
    spillsets,
    no_share_edges,
    core_block_order(self.ranges.block_order),
  )

  // 3) Rewrite all spill-slot references (spill map + constraint edits).
  for vreg_id, old_slot in result.spill_slots {
    if remap_lookup(compaction.remaps, old_slot) is Some(new_slot) {
      result.spill_slots.set(vreg_id, new_slot)
    }
  }
  for entry in result.inst_edits {
    let (_, _, edits) = entry
    for i in 0..<edits.before.length() {
      let mv = edits.before[i]
      let from = match mv.from {
        Spill(s) =>
          match remap_lookup(compaction.remaps, s) {
            Some(ns) => Loc::Spill(ns)
            None => mv.from
          }
        _ => mv.from
      }
      let to = match mv.to {
        Spill(s) =>
          match remap_lookup(compaction.remaps, s) {
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
          match remap_lookup(compaction.remaps, s) {
            Some(ns) => Loc::Spill(ns)
            None => mv.from
          }
        _ => mv.from
      }
      let to = match mv.to {
        Spill(s) =>
          match remap_lookup(compaction.remaps, s) {
            Some(ns) => Loc::Spill(ns)
            None => mv.to
          }
        _ => mv.to
      }
      edits.after[i] = { from, to, class: mv.class }
    }
  }

  // 4) Return total spill-slot count.
  compaction.total_slots
}

///|
/// Build bundles with merging from Move instructions and block arguments
pub fn build_bundles_with_merging(
  func : VCodeFunction,
  ranges : LiveRangeSet,
) -> BundleSet {
  let n = ranges.length()
  let num_blocks = func.blocks.length()
  let block_lengths_by_order : Array[Int] = Array::make(num_blocks, 0)
  for block_idx in 0..<num_blocks {
    block_lengths_by_order[ranges.block_order[block_idx]] = (
        func.blocks[block_idx].insts.length() + 2
      ) *
      2
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

  let core_ranges : Array[@core_regalloc.BundleMergeRange] = []
  for i in 0..<n {
    let range = ranges.get(i)
    let (fixed_reg, fixed_conflict) = range_fixed_reg_conflict(range)
    let core_spans : Array[@core_regalloc.ProgramRange] = []
    for span in range.ranges {
      core_spans.push(
        @core_regalloc.ProgramRange::new(
          backtrack_core_point(span.start),
          backtrack_core_point(span.end),
        ),
      )
    }
    core_ranges.push({
      id: i,
      class: backtrack_core_reg_class(range.vreg.class),
      ranges: core_spans,
      fixed_reg: fixed_reg.map(backtrack_core_preg),
      has_fixed_conflict: fixed_conflict,
      has_fixed_def: range_has_fixed_def(range),
    })
  }
  let merge_edges : Array[@core_regalloc.BundleMergeEdge] = []
  for pair in ranges.blockparam_out_pairs {
    let (param_idx, arg_idx) = pair
    if arg_idx != param_idx {
      merge_edges.push({ target: param_idx, source: arg_idx })
    }
  }
  let plan = @core_regalloc.plan_bundle_merges(
    core_ranges,
    merge_edges,
    backtrack_core_block_order(ranges.block_order),
    block_lengths_by_order,
  )
  let result = BundleSet::new()
  for bundle_id in 0..<plan.bundle_roots.length() {
    let root = plan.bundle_roots[bundle_id]
    let first_range = ranges.get(root)
    result.add_bundle(Bundle::new(bundle_id, first_range.vreg.class))
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
      merged_ranges.push(backtrack_old_range(span))
    }
    bundle.merged_ranges = Some(merged_ranges)
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
  strict_precolor : Bool,
) -> Unit {
  let isa = @isa.ISA::current()
  let vmctx_preg = isa.wasm_vmctx_arg_preg()
  let user_arg_gprs = isa.wasm_user_arg_gprs()
  let arg_fprs = isa.wasm_arg_fprs()
  let mut int_idx = 0
  let mut float_idx = 0
  for param in self.func.params {
    let is_vmctx_param = param.class is Int && int_idx == 0
    // Determine which ABI register this param comes in
    let (preg_opt, is_int) : (@abi.PReg?, Bool) = match param.class {
      Int =>
        if int_idx == 0 {
          // First integer argument is always vmctx in the internal Wasm ABI.
          (Some(vmctx_preg), true)
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
        if is_vmctx_param {
          self.record_allocation(bundle, isa.vmctx_preg())
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
        if !assigned &&
          bundle.spillset_id >= 0 &&
          bundle.spillset_id < self.spillset_hints.length() {
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
            self.spillset_hints[bundle.spillset_id] = Some(hint_preg)
          }
        }
        continue
      }

      // Normal case:
      // - strict mode: pin param bundle to incoming ABI register.
      // - relaxed mode: keep vmctx pinned, but treat other params as hints only.
      if strict_precolor || is_vmctx_param {
        self.record_allocation(bundle, preg)
        // Keep VMContext pinned. For strict precoloring, only pin params that
        // do not cross calls; call-crossing values must remain movable so the
        // allocator can satisfy call-clobber constraints.
        if is_vmctx_param ||
          (strict_precolor && !bundle.crosses_call(self.ranges)) {
          bundle.is_pinned = true
        }
      } else if bundle.spillset_id >= 0 &&
        bundle.spillset_id < self.spillset_hints.length() {
        self.spillset_hints[bundle.spillset_id] = Some(preg)
      }
    }
  }
}

///|
/// Main entry point for backtracking allocation
pub fn allocate_backtracking(
  func : VCodeFunction,
  liveness : LivenessResult,
  int_regs : Array[@abi.PReg],
  float_regs : Array[@abi.PReg],
  vector_regs : Array[@abi.PReg],
  callee_saved_int : Array[@abi.PReg],
  callee_saved_float : Array[@abi.PReg],
  param_precolor_strict? : Bool = true,
  algorithm? : RegallocAlgorithm = Backtracking,
) -> RegAllocResult {
  let perf_on = @perf.enabled()

  // Phase 2: Build LiveRanges
  let tick_live_ranges = if perf_on { Some(@perf.tick_now()) } else { None }
  let ranges = build_live_ranges(func, liveness)
  if tick_live_ranges is Some(tick) {
    @perf.record_regalloc_phase_us("phase_live_ranges", @perf.elapsed_us(tick))
  }

  // Phase 3: Build Bundles with merging
  let tick_bundles = if perf_on { Some(@perf.tick_now()) } else { None }
  let bundles = build_bundles_with_merging(func, ranges)
  if tick_bundles is Some(tick) {
    @perf.record_regalloc_phase_us("phase_bundle_merge", @perf.elapsed_us(tick))
  }

  // Phase 4: Allocate
  let tick_alloc_new = if perf_on { Some(@perf.tick_now()) } else { None }
  let allocator = BacktrackingAllocator::new(
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
    @perf.record_regalloc_phase_us(
      "phase_allocator_new",
      @perf.elapsed_us(tick),
    )
  }

  // Pre-assign function parameters to ABI registers (before main allocation)
  let tick_preassign = if perf_on { Some(@perf.tick_now()) } else { None }
  allocator.preassign_params(param_precolor_strict)
  if tick_preassign is Some(tick) {
    @perf.record_regalloc_phase_us(
      "phase_preassign_params",
      @perf.elapsed_us(tick),
    )
  }
  let tick_allocate = if perf_on { Some(@perf.tick_now()) } else { None }
  allocator.allocate()
  if tick_allocate is Some(tick) {
    @perf.record_regalloc_phase_us(
      "phase_allocate_main",
      @perf.elapsed_us(tick),
    )
  }

  // Generate result
  let tick_result = if perf_on { Some(@perf.tick_now()) } else { None }
  let result = allocator.generate_result()
  if tick_result is Some(tick) {
    @perf.record_regalloc_phase_us(
      "phase_generate_result",
      @perf.elapsed_us(tick),
    )
  }
  result
}
