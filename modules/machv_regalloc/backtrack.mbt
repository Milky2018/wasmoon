// Ion-Style Backtracking Register Allocator
// Main allocator implementation with bundle merging, eviction, and splitting.

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
/// Priority queue entry for allocation
priv struct QueueEntry {
  bundle_id : Int
  prio : Int
  hint_preg : @abi.PReg?
  // Insertion order for stable tie-breaking (monotonic).
  seq : Int
}

///|
/// Ordering for the allocator queue (max-heap).
/// Higher priority gets popped first; ties keep the historical stable behavior.
fn queue_entry_higher(a : QueueEntry, b : QueueEntry) -> Bool {
  if a.prio > b.prio {
    true
  } else if a.prio < b.prio {
    false
  } else if a.seq != b.seq {
    a.seq < b.seq
  } else {
    a.bundle_id < b.bundle_id
  }
}

///|
/// Check whether two pregs refer to the same hardware register bank + index.
fn preg_same_bank_and_index(a : @abi.PReg, b : @abi.PReg) -> Bool {
  a.index == b.index && reg_class_compatible(a.class, b.class)
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
/// Bundle-merge working span with cached order keys.
priv struct MergeSpan {
  span : ProgPointRange
  start_ord : Int
  start_before_ord : Int
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

  // Priority queue of bundles to process
  mut queue : Array[QueueEntry] // max-heap by QueueEntry.prio
  mut queue_next_seq : Int
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
  // Per-allocation-query seen markers for conflict dedup (bundle-id indexed).
  conflict_seen_epoch : Array[Int]
  mut conflict_epoch : Int
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
  let entry : QueueEntry = {
    bundle_id,
    prio,
    hint_preg,
    seq: self.queue_next_seq,
  }
  self.queue_next_seq = self.queue_next_seq + 1
  self.queue.push(entry)
  if bundle_id >= 0 && bundle_id < self.queue_in_heap.length() {
    self.queue_in_heap[bundle_id] = true
  }
  // Sift up.
  let mut i = self.queue.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if queue_entry_higher(self.queue[i], self.queue[parent]) {
      let tmp = self.queue[i]
      self.queue[i] = self.queue[parent]
      self.queue[parent] = tmp
      i = parent
    } else {
      break
    }
  }
}

///|
/// Heap pop-max from the allocator queue.
fn BacktrackingAllocator::queue_pop(
  self : BacktrackingAllocator,
) -> QueueEntry? {
  if self.queue.is_empty() {
    return None
  }
  // Remove root.
  let top = self.queue[0]
  if top.bundle_id >= 0 && top.bundle_id < self.queue_in_heap.length() {
    self.queue_in_heap[top.bundle_id] = false
  }
  let last = self.queue.pop()
  match last {
    None => None
    Some(v) => {
      if !self.queue.is_empty() {
        self.queue[0] = v
        // Sift down.
        let mut i = 0
        while true {
          let left = i * 2 + 1
          if left >= self.queue.length() {
            break
          }
          let right = left + 1
          let mut best = left
          if right < self.queue.length() &&
            queue_entry_higher(self.queue[right], self.queue[left]) {
            best = right
          }
          if queue_entry_higher(self.queue[best], self.queue[i]) {
            let tmp = self.queue[i]
            self.queue[i] = self.queue[best]
            self.queue[best] = tmp
            i = best
          } else {
            break
          }
        }
      }
      Some(top)
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
    queue: [],
    queue_next_seq: 0,
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
    conflict_seen_epoch: Array::make(bundles.length(), 0),
    conflict_epoch: 0,
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
  self.queue = []
  self.queue_next_seq = 0
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
  let do_preferred_pass = self.enable_backtracking &&
    !bundle.crosses_call(self.ranges) &&
    (
      bundle.reg_class is Int ||
      bundle.reg_class is Float32 ||
      bundle.reg_class is Float64
    )
  let reg_class = bundle.reg_class
  let phase_count = if do_preferred_pass { 2 } else { 1 }
  let scan_limit = if self.split_probe_limit < n {
    self.split_probe_limit
  } else {
    n
  }
  let raw_phase_offset = bundle.id + start_inst
  for phase in 0..<phase_count {
    let phase_regs = if do_preferred_pass {
      if phase == 0 {
        match reg_class {
          Int => self.int_caller_saved
          Float32 | Float64 => self.float_caller_saved
          Vector => avail_regs
        }
      } else {
        match reg_class {
          Int => self.callee_saved_int
          Float32 | Float64 => self.callee_saved_float
          Vector => []
        }
      }
    } else {
      avail_regs
    }
    let phase_n = phase_regs.length()
    if phase_n == 0 {
      continue
    }
    let phase_scan_limit = if scan_limit < phase_n {
      scan_limit
    } else {
      phase_n
    }
    let phase_offset = (raw_phase_offset % phase_n + phase_n) % phase_n
    let mut scanned = 0
    for i in 0..<phase_n {
      if scanned >= phase_scan_limit {
        break
      }
      let preg = phase_regs[(phase_offset + i) % phase_n]
      if hint_preg is Some(hint) && preg_same_bank_and_index(preg, hint) {
        continue
      }
      scanned = scanned + 1
      if !self.has_conflict_on_preg_with_spans(spans, preg) {
        return Some(preg)
      }
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
  self.conflict_epoch = self.conflict_epoch + 1
  let seen_epoch = self.conflict_epoch
  let mut max_conflict_weight = 0
  let mut first_conflict_point : ProgPoint? = None
  let allocs = self.get_reg_allocs(preg.class)
  if preg.index < 0 || preg.index >= allocs.length() {
    return (max_conflict_weight, first_conflict_point, false)
  }
  let occupied = allocs[preg.index]
  if occupied.is_empty() || spans.is_empty() {
    return (max_conflict_weight, first_conflict_point, false)
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
    if first_conflict_point is None {
      first_conflict_point = Some(
        if span.start_ord >= occ.start_ord {
          span.start
        } else {
          occ.start
        },
      )
    }
    let other_id = occupied[j].0
    if self.conflict_seen_epoch[other_id] != seen_epoch {
      self.conflict_seen_epoch[other_id] = seen_epoch
      let other = self.bundles.get(other_id)
      if other.is_pinned || other.spill_weight >= bundle.spill_weight {
        conflicts.clear()
        return (0, first_conflict_point, true)
      }
      conflicts.push(other_id)
      if other.spill_weight > max_conflict_weight {
        max_conflict_weight = other.spill_weight
        if max_allowable_cost is Some(limit) && max_conflict_weight > limit {
          conflicts.clear()
          return (0, first_conflict_point, true)
        }
      }
    }
    if span.end_ord <= occ.end_ord {
      i = i + 1
    } else {
      j = j + 1
    }
  }
  (max_conflict_weight, first_conflict_point, false)
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
  let do_preferred_pass = self.enable_backtracking &&
    !bundle.crosses_call(self.ranges) &&
    (
      bundle.reg_class is Int ||
      bundle.reg_class is Float32 ||
      bundle.reg_class is Float64
    )
  let reg_class = bundle.reg_class
  let phase_count = if do_preferred_pass { 2 } else { 1 }
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
  for phase in 0..<phase_count {
    let phase_regs = if do_preferred_pass {
      if phase == 0 {
        match reg_class {
          Int => self.int_caller_saved
          Float32 | Float64 => self.float_caller_saved
          Vector => avail_regs
        }
      } else {
        match reg_class {
          Int => self.callee_saved_int
          Float32 | Float64 => self.callee_saved_float
          Vector => []
        }
      }
    } else {
      avail_regs
    }
    let phase_n = phase_regs.length()
    if phase_n == 0 {
      continue
    }
    let phase_scan_limit = if scan_limit < phase_n {
      scan_limit
    } else {
      phase_n
    }
    let phase_offset = (raw_phase_offset % phase_n + phase_n) % phase_n
    let mut scanned = 0
    for i in 0..<phase_n {
      if scanned >= phase_scan_limit {
        break
      }
      let preg = phase_regs[(phase_offset + i) % phase_n]
      scanned = scanned + 1
      // regalloc2-style high-cost cutoff:
      // when we already have a best candidate (evict/split), stop considering
      // higher-cost registers early.
      let cutoff = match (best_conflict_cost, best_split_cost) {
        (Some(a), Some(b)) => Some(if a > b { a } else { b })
        (Some(a), None) => Some(a)
        (None, Some(b)) => Some(b)
        (None, None) => None
      }
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
        match (best_split_cost, best_split) {
          (None, None) => {
            best_split_cost = Some(max_conflict_weight)
            best_split = Some((point, preg))
          }
          (Some(existing_cost), Some((existing_point, _existing_preg))) =>
            if max_conflict_weight < existing_cost {
              best_split_cost = Some(max_conflict_weight)
              best_split = Some((point, preg))
            } else if max_conflict_weight == existing_cost &&
              point.compare_with_order(existing_point, self.block_order) > 0 {
              best_split_cost = Some(max_conflict_weight)
              best_split = Some((point, preg))
            }
          _ => ()
        }
      }

      // Keep only legal eviction candidates.
      // Mirrors regalloc2's "lowest conflict cost" selection strategy:
      // - reject pinned / heavier-or-equal conflicts
      // - choose the candidate with minimum maximum conflict spill weight.
      let mut take_candidate = false
      match best_conflict_cost {
        None => take_candidate = true
        Some(existing_cost) =>
          if max_conflict_weight < existing_cost {
            take_candidate = true
          } else if max_conflict_weight == existing_cost {
            // Tie-break: prefer the hint register if one is provided.
            if hint_preg is Some(hint) &&
              preg_same_bank_and_index(preg, hint) &&
              best_preg is Some(current_best) &&
              !preg_same_bank_and_index(current_best, hint) {
              take_candidate = true
            }
          }
      }
      if take_candidate {
        best_preg = Some(preg)
        best_conflict_cost = Some(max_conflict_weight)
        best_conflicts.clear()
        for conflict_id in scratch_conflicts {
          best_conflicts.push(conflict_id)
        }
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
  if spillset_id >= 0 &&
    spillset_id < self.spillset_split_counts.length() &&
    self.spillset_split_counts[spillset_id] >= self.max_splits_per_spillset {
    self.split_into_minimal_bundles(bundle, split_hint)
    return
  }

  match split_opt {
    Some((split_point, split_hint_reg)) => {
      if spillset_id >= 0 && spillset_id < self.spillset_split_counts.length() {
        self.spillset_split_counts[spillset_id] = self.spillset_split_counts[spillset_id] +
          1
      }
      // Split the bundle at this point
      // Create two new bundles: before and after the split point
      let spill_bundle = self.bundles.get_or_create_spill_bundle(bundle)

      // Partition ranges into before/after split point
      let before_ranges : Array[Int] = []
      let after_ranges : Array[Int] = []
      for range_id in bundle.range_ids {
        let range = self.ranges.get(range_id)
        if range.end(self.block_order) is Some(end_point) {
          if end_point.compare_with_order(split_point, self.block_order) <= 0 {
            before_ranges.push(range_id)
          } else if range.start(self.block_order) is Some(start_point) {
            if start_point.compare_with_order(split_point, self.block_order) >=
              0 {
              after_ranges.push(range_id)
            } else {
              // Range spans the split point - assign to after for simplicity
              // A more sophisticated implementation would split the range itself
              after_ranges.push(range_id)
            }
          } else {
            after_ranges.push(range_id)
          }
        } else {
          after_ranges.push(range_id)
        }
      }

      // If we couldn't split effectively, just spill
      if before_ranges.is_empty() || after_ranges.is_empty() {
        self.split_into_minimal_bundles(bundle, Some(split_hint_reg))
        return
      }

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
      self.conflict_seen_epoch.push(0)
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
      self.conflict_seen_epoch.push(0)
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
    None => {
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
  self.conflict_seen_epoch.push(0)
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
    let bundle = self.bundles.get(entry.bundle_id)
    let hint_preg = match entry.hint_preg {
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
    if entry.bundle_id >= 0 && entry.bundle_id < self.bundle_attempts.length() {
      self.bundle_attempts[entry.bundle_id] = self.bundle_attempts[entry.bundle_id] +
        1
      if self.bundle_attempts[entry.bundle_id] > self.bundle_retry_limit &&
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
priv struct SpillSetInfo {
  old_slot : Int
  reg_class : @abi.RegClass
  spans : Array[ProgPointRange]
  start : ProgPoint
}

///|
priv struct AssignedSlot {
  start : Int
  spans : Array[ProgPointRange]
  old_slots : Array[Int]
}

///|
/// Compact spill slots by reusing them across non-overlapping spill bundles.
fn BacktrackingAllocator::compact_spill_slots(
  self : BacktrackingAllocator,
  result : RegAllocResult,
) -> Int {
  fn slots_used(cls : @abi.RegClass) -> Int {
    match cls {
      Vector => 2
      _ => 1
    }
  }

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

  fn add_no_share_edge(
    no_share : Map[Int, Set[Int]],
    a : Int,
    b : Int,
  ) -> Unit {
    if a == b {
      return
    }
    if no_share.get(a) is None {
      no_share.set(a, Set([]))
    }
    no_share.get(a).unwrap().add(b) |> ignore
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
  let no_share : Map[Int, Set[Int]] = {}
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
          add_no_share_edge(no_share, slots[i], slots[j])
          add_no_share_edge(no_share, slots[j], slots[i])
        }
      }
    }
  }

  // 3) Assign spillsets to a compact set of physical spill slots.
  let scalar_slots : Array[AssignedSlot] = []
  let vector_slots : Array[AssignedSlot] = []
  let slot_remap : Map[Int, Int] = {}
  let mut next_slot = 0
  for ss in spillsets {
    let used = slots_used(ss.reg_class)
    let pool = if used == 2 { vector_slots } else { scalar_slots }
    let mut placed = false
    for slot in pool {
      let mut edge_conflict = false
      if no_share.get(ss.old_slot) is Some(disallowed) {
        for existing_old_slot in slot.old_slots {
          if disallowed.contains(existing_old_slot) {
            edge_conflict = true
            break
          }
        }
      }
      if !edge_conflict &&
        !spans_overlap(ss.spans, slot.spans, self.ranges.block_order) {
        slot_remap.set(ss.old_slot, slot.start)
        // Extend occupancy for future overlap checks.
        for span in ss.spans {
          slot.spans.push(span)
        }
        slot.old_slots.push(ss.old_slot)
        placed = true
        break
      }
    }
    if placed {
      continue
    }

    // Allocate a fresh slot (respect vector alignment).
    if used == 2 && next_slot % 2 != 0 {
      next_slot += 1
    }
    let new_slot = next_slot
    next_slot += used
    let new_spans : Array[ProgPointRange] = []
    for span in ss.spans {
      new_spans.push(span)
    }
    pool.push({ start: new_slot, spans: new_spans, old_slots: [ss.old_slot] })
    slot_remap.set(ss.old_slot, new_slot)
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
  next_slot
}

///|
/// Build bundles with merging from Move instructions and block arguments
pub fn build_bundles_with_merging(
  func : VCodeFunction,
  ranges : LiveRangeSet,
) -> BundleSet {
  let perf_on = perf_enabled()
  let n = ranges.length()
  let uf = @unionfind.UnionFind::new(n)
  // regalloc2/ion always performs bundle coalescing, bounded by overlap and
  // complexity guards inside merge checks.
  let block_param_merge_enabled = true
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

  fn clone_spans(spans : Array[MergeSpan]) -> Array[MergeSpan] {
    let out : Array[MergeSpan] = []
    for span in spans {
      out.push(span)
    }
    out
  }

  fn insert_sorted_span(spans : Array[MergeSpan], insert : MergeSpan) -> Unit {
    let insert_ord = insert.start_ord
    let mut lo = 0
    let mut hi = spans.length()
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      let mid_ord = spans[mid].start_ord
      if mid_ord <= insert_ord {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    spans.insert(lo, insert)
  }

  // Keep merged-span buffers owned/cached by root and mutate only cache-owned
  // arrays; never mutate original per-range span arrays in LiveRangeSet.
  fn root_spans_owned(
    root_spans_cache : Array[Array[MergeSpan]?],
    root : Int,
    fallback : Array[MergeSpan],
  ) -> Array[MergeSpan] {
    match root_spans_cache[root] {
      Some(spans) => spans
      None => {
        // If fallback is exactly the source range's spans, clone once to get
        // an owned mutable buffer for this root cache entry.
        let owned = clone_spans(fallback)
        root_spans_cache[root] = Some(owned)
        owned
      }
    }
  }

  fn merge_into_root_spans(
    root_spans_cache : Array[Array[MergeSpan]?],
    target_root : Int,
    target_fallback : Array[MergeSpan],
    source_spans : Array[MergeSpan],
  ) -> Array[MergeSpan] {
    if source_spans.is_empty() {
      return root_spans_owned(root_spans_cache, target_root, target_fallback)
    }
    if target_fallback.is_empty() {
      // regalloc2 merge.rs empty-target fast path: move source list directly.
      root_spans_cache[target_root] = Some(source_spans)
      return source_spans
    }
    let target_spans = root_spans_owned(
      root_spans_cache, target_root, target_fallback,
    )
    if source_spans.length() == 1 {
      insert_sorted_span(target_spans, source_spans[0])
      return target_spans
    }
    // Keep merge semantics equivalent to regalloc2 while avoiding
    // full re-sort on every merge in MoonBit's runtime.
    let merged : Array[MergeSpan] = []
    let mut i = 0
    let mut j = 0
    while i < target_spans.length() && j < source_spans.length() {
      if target_spans[i].start_ord <= source_spans[j].start_ord {
        merged.push(target_spans[i])
        i += 1
      } else {
        merged.push(source_spans[j])
        j += 1
      }
    }
    while i < target_spans.length() {
      merged.push(target_spans[i])
      i += 1
    }
    while j < source_spans.length() {
      merged.push(source_spans[j])
      j += 1
    }
    root_spans_cache[target_root] = Some(merged)
    merged
  }

  let root_fixed_reg_cache : Array[@abi.PReg?] = []
  let root_fixed_conflict_cache : Array[Bool] = []
  let root_has_fixed_def_cache : Array[Bool] = []
  let root_spans_cache : Array[Array[MergeSpan]?] = Array::make(n, None)
  let mut merge_span_fetch_us = 0L
  let mut merge_overlap_scan_us = 0L
  let mut merge_commit_us = 0L
  let tick_init_metadata = if perf_on { Some(perf_tick_now()) } else { None }
  // Initialize per-root fixed-info metadata so merges stay incremental.
  // Keep span vectors lazy (on-demand) to avoid up-front copy/sort work for
  // roots that never participate in merges.
  for i in 0..<n {
    let range = ranges.get(i)
    let (fixed_reg, fixed_conflict) = range_fixed_reg_conflict(range)
    root_fixed_reg_cache.push(fixed_reg)
    root_fixed_conflict_cache.push(fixed_conflict)
    root_has_fixed_def_cache.push(range_has_fixed_def(range))
  }
  if tick_init_metadata is Some(tick) {
    perf_record_regalloc_phase_us(
      "phase_bundle_merge_init",
      perf_elapsed_us(tick),
    )
  }

  fn root_fixed_info(
    ranges : LiveRangeSet,
    root_fixed_reg_cache : Array[@abi.PReg?],
    root_fixed_conflict_cache : Array[Bool],
    root : Int,
  ) -> (@abi.PReg?, Bool) {
    ignore(ranges)
    (root_fixed_reg_cache[root], root_fixed_conflict_cache[root])
  }

  fn root_has_fixed_def(
    ranges : LiveRangeSet,
    root_has_fixed_def_cache : Array[Bool],
    root : Int,
  ) -> Bool {
    ignore(ranges)
    root_has_fixed_def_cache[root]
  }

  fn root_spans(
    ranges : LiveRangeSet,
    root_spans_cache : Array[Array[MergeSpan]?],
    root : Int,
  ) -> Array[MergeSpan] {
    match root_spans_cache[root] {
      Some(spans) => spans
      None => {
        let range = ranges.get(root)
        let spans : Array[MergeSpan] = []
        for span in range.ranges {
          spans.push(
            make_merge_span(span, ranges.block_order, block_point_base),
          )
        }
        root_spans_cache[root] = Some(spans)
        spans
      }
    }
  }

  // Helper to try merging two ranges
  fn commit_union(
    uf : @unionfind.UnionFind,
    root_a : Int,
    root_b : Int,
    fixed_a : @abi.PReg?,
    fixed_b : @abi.PReg?,
    set_a_has_fixed_def : Bool,
    set_b_has_fixed_def : Bool,
    spans_a : Array[MergeSpan],
    spans_b : Array[MergeSpan],
  ) -> Bool {
    // Keep directional merge semantics close to regalloc2/ion:
    // merge `root_b` into `root_a` so the caller-chosen "to" root stays
    // stable across repeated merges.
    if !uf.union_into(root_b, root_a) {
      return true
    }
    let new_root = uf.find(root_a)
    let old_root = if new_root == root_a { root_b } else { root_a }
    let merged_fixed_def = set_a_has_fixed_def || set_b_has_fixed_def
    root_has_fixed_def_cache[new_root] = merged_fixed_def
    root_has_fixed_def_cache[old_root] = merged_fixed_def
    let merged_fixed = match (fixed_a, fixed_b) {
      (Some(preg), _) => Some(preg)
      (_, Some(preg)) => Some(preg)
      _ => None
    }
    root_fixed_reg_cache[new_root] = merged_fixed
    root_fixed_conflict_cache[new_root] = false
    root_fixed_reg_cache[old_root] = merged_fixed
    root_fixed_conflict_cache[old_root] = false
    let (target_spans, source_spans) = if new_root == root_a {
      (spans_a, spans_b)
    } else {
      (spans_b, spans_a)
    }
    let merged_spans = merge_into_root_spans(
      root_spans_cache, new_root, target_spans, source_spans,
    )
    root_spans_cache[new_root] = Some(merged_spans)
    root_spans_cache[old_root] = None
    true
  }

  // Helper to try merging two ranges
  fn try_merge(
    uf : @unionfind.UnionFind,
    a : Int,
    b : Int,
    ranges : LiveRangeSet,
  ) -> Bool {
    if a < 0 || b < 0 || a >= ranges.length() || b >= ranges.length() {
      return false
    }
    let root_a = uf.find(a)
    let root_b = uf.find(b)
    if root_a == root_b {
      return true
    }
    let range_a = ranges.get(a)
    let range_b = ranges.get(b)

    // Must be same register class
    if !reg_class_compatible(range_a.vreg.class, range_b.vreg.class) {
      return false
    }
    let set_a_has_fixed_def = root_has_fixed_def(
      ranges, root_has_fixed_def_cache, root_a,
    )
    let set_b_has_fixed_def = root_has_fixed_def(
      ranges, root_has_fixed_def_cache, root_b,
    )

    // Keep merged bundles compatible with fixed-register constraints.
    // This follows regalloc2's spirit: avoid forcing one bundle to satisfy
    // incompatible fixed uses.
    let (fixed_a, conflict_a) = root_fixed_info(
      ranges, root_fixed_reg_cache, root_fixed_conflict_cache, root_a,
    )
    let (fixed_b, conflict_b) = root_fixed_info(
      ranges, root_fixed_reg_cache, root_fixed_conflict_cache, root_b,
    )
    if conflict_a || conflict_b {
      return false
    }
    if fixed_a is Some(a_fixed) &&
      fixed_b is Some(b_fixed) &&
      (a_fixed.index != b_fixed.index || !same_fixed_bank(a_fixed, b_fixed)) {
      return false
    }

    // Check for overlap within potential merged bundle.
    // Follow regalloc2's merge scan style: compare sorted range starts with
    // two cursors and stop early when one side advances past the other.
    let tick_span_fetch = if perf_on { Some(perf_tick_now()) } else { None }
    let spans_a = root_spans(ranges, root_spans_cache, root_a)
    let spans_b = root_spans(ranges, root_spans_cache, root_b)
    if tick_span_fetch is Some(tick) {
      merge_span_fetch_us = merge_span_fetch_us + perf_elapsed_us(tick)
    }
    let adjust_a = set_a_has_fixed_def
    let adjust_b = set_b_has_fixed_def
    let tick_overlap_scan = if perf_on { Some(perf_tick_now()) } else { None }
    if !spans_a.is_empty() && !spans_b.is_empty() {
      let start_a_ord = if adjust_a {
        spans_a[0].start_before_ord
      } else {
        spans_a[0].start_ord
      }
      let end_a_ord = spans_a[spans_a.length() - 1].end_ord
      let start_b_ord = if adjust_b {
        spans_b[0].start_before_ord
      } else {
        spans_b[0].start_ord
      }
      let end_b_ord = spans_b[spans_b.length() - 1].end_ord
      let disjoint = start_a_ord >= end_b_ord || start_b_ord >= end_a_ord
      if disjoint {
        if tick_overlap_scan is Some(tick) {
          merge_overlap_scan_us = merge_overlap_scan_us + perf_elapsed_us(tick)
        }
        let tick_commit = if perf_on { Some(perf_tick_now()) } else { None }
        let merged = commit_union(
          uf, root_a, root_b, fixed_a, fixed_b, set_a_has_fixed_def, set_b_has_fixed_def,
          spans_a, spans_b,
        )
        if tick_commit is Some(tick) {
          merge_commit_us = merge_commit_us + perf_elapsed_us(tick)
        }
        return merged
      }
    }
    let mut ia = 0
    let mut ib = 0
    let mut range_checks = 0
    while ia < spans_a.length() && ib < spans_b.length() {
      range_checks += 1
      if range_checks > 200 {
        if tick_overlap_scan is Some(tick) {
          merge_overlap_scan_us = merge_overlap_scan_us + perf_elapsed_us(tick)
        }
        return false
      }
      let span_a = spans_a[ia]
      let span_b = spans_b[ib]
      let start_a_ord = if adjust_a {
        span_a.start_before_ord
      } else {
        span_a.start_ord
      }
      let end_a_ord = span_a.end_ord
      let start_b_ord = if adjust_b {
        span_b.start_before_ord
      } else {
        span_b.start_ord
      }
      let end_b_ord = span_b.end_ord
      if start_a_ord >= end_b_ord {
        ib = ib + 1
      } else if start_b_ord >= end_a_ord {
        ia = ia + 1
      } else {
        if tick_overlap_scan is Some(tick) {
          merge_overlap_scan_us = merge_overlap_scan_us + perf_elapsed_us(tick)
        }
        return false
      }
    }
    if tick_overlap_scan is Some(tick) {
      merge_overlap_scan_us = merge_overlap_scan_us + perf_elapsed_us(tick)
    }
    let tick_commit = if perf_on { Some(perf_tick_now()) } else { None }
    let merged = commit_union(
      uf, root_a, root_b, fixed_a, fixed_b, set_a_has_fixed_def, set_b_has_fixed_def,
      spans_a, spans_b,
    )
    if tick_commit is Some(tick) {
      merge_commit_us = merge_commit_us + perf_elapsed_us(tick)
    }
    merged
  }

  let tick_merge_blockargs = if perf_on { Some(perf_tick_now()) } else { None }
  // Merge across block arguments (SSA phi-like connections).
  if block_param_merge_enabled {
    for pair in ranges.blockparam_out_pairs {
      let (param_idx, arg_idx) = pair
      if arg_idx == param_idx {
        continue
      }
      try_merge(uf, param_idx, arg_idx, ranges) |> ignore
    }
  }
  if tick_merge_blockargs is Some(tick) {
    perf_record_regalloc_phase_us(
      "phase_bundle_merge_blockargs",
      perf_elapsed_us(tick),
    )
    perf_record_regalloc_phase_us(
      "phase_bundle_merge_spans", merge_span_fetch_us,
    )
    perf_record_regalloc_phase_us(
      "phase_bundle_merge_overlap", merge_overlap_scan_us,
    )
    perf_record_regalloc_phase_us("phase_bundle_merge_commit", merge_commit_us)
  }

  let tick_finalize = if perf_on { Some(perf_tick_now()) } else { None }
  // Build final bundles from union-find roots (dense-indexed, regalloc2-style).
  let result = BundleSet::new()
  let root_to_bundle : Array[Int] = Array::make(n, -1)
  let bundle_to_root : Array[Int] = []
  for range_idx in 0..<n {
    let root = uf.find(range_idx)
    let bundle_id = root_to_bundle[root]
    let bundle = if bundle_id >= 0 {
      result.get(bundle_id)
    } else {
      let first_range = ranges.get(range_idx)
      let created = Bundle::new(result.bundles.length(), first_range.vreg.class)
      result.add_bundle(created)
      let new_id = created.id
      root_to_bundle[root] = new_id
      bundle_to_root.push(root)
      created
    }
    bundle.add_range(range_idx)
    ranges.get(range_idx).bundle_id = bundle.id
  }
  for bundle_id in 0..<result.bundles.length() {
    let root = bundle_to_root[bundle_id]
    let bundle = result.get(bundle_id)
    let merged_ranges : Array[ProgPointRange] = []
    match root_spans_cache[root] {
      Some(spans) =>
        for span in spans {
          merged_ranges.push(span.span)
        }
      None => {
        // No merge cache materialized for this root: keep the original
        // normalized ranges directly, avoiding redundant MergeSpan conversion.
        let root_range = ranges.get(root)
        for span in root_range.ranges {
          merged_ranges.push(span)
        }
      }
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
    perf_record_regalloc_phase_us("phase_allocator_new", perf_elapsed_us(tick))
  }

  // Pre-assign function parameters to ABI registers (before main allocation)
  let tick_preassign = if perf_on { Some(perf_tick_now()) } else { None }
  allocator.preassign_params(param_precolor_strict)
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
