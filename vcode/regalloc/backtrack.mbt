// Ion-Style Backtracking Register Allocator
// Main allocator implementation with bundle merging, eviction, and splitting.

///|
/// Check if two register classes are compatible
fn reg_class_compatible(a : @abi.RegClass, b : @abi.RegClass) -> Bool {
  match (a, b) {
    (@abi.Int, @abi.Int) => true
    (@abi.Float32, @abi.Float32) => true
    (@abi.Float32, @abi.Float64) => true
    (@abi.Float32, @abi.Vector) => true
    (@abi.Float64, @abi.Float32) => true
    (@abi.Float64, @abi.Float64) => true
    (@abi.Float64, @abi.Vector) => true
    (@abi.Vector, @abi.Float32) => true
    (@abi.Vector, @abi.Float64) => true
    (@abi.Vector, @abi.Vector) => true
    _ => false
  }
}

///|
/// Priority queue entry for allocation
priv struct QueueEntry {
  bundle_id : Int
  weight : Double
  hint_preg : @abi.PReg?
  // Insertion order for stable tie-breaking (monotonic).
  seq : Int
}

///|
/// Ordering for the allocator queue (max-heap).
/// Higher weight gets popped first; ties keep the historical stable behavior.
fn queue_entry_higher(a : QueueEntry, b : QueueEntry) -> Bool {
  if a.weight > b.weight {
    true
  } else if a.weight < b.weight {
    false
  } else if a.seq != b.seq {
    a.seq < b.seq
  } else {
    a.bundle_id < b.bundle_id
  }
}

///|
/// The backtracking register allocator
struct BacktrackingAllocator {
  // Core data
  ranges : LiveRangeSet
  bundles : BundleSet

  // Physical register occupancy: preg.index -> list of occupied ranges
  //
  // Each entry stores (bundle_id, span) so eviction/removal cannot accidentally
  // remove spans that belong to a different bundle with identical boundaries.
  int_reg_allocs : Map[Int, Array[(Int, ProgPointRange)]]
  float_reg_allocs : Map[Int, Array[(Int, ProgPointRange)]]

  // Index: preg.index -> set of bundle IDs allocated to this register
  // Used for fast conflict lookup in find_conflicts
  int_reg_bundles : Map[Int, Set[Int]]
  float_reg_bundles : Map[Int, Set[Int]]

  // Priority queue of bundles to process
  mut queue : Array[QueueEntry] // max-heap by QueueEntry.weight
  mut queue_next_seq : Int

  // Cranelift-style spillset hint: remember last successful preg for an
  // "original" bundle (spillset), and prefer it for split pieces.
  spillset_hints : Array[@abi.PReg?]

  // Configuration
  int_regs : Array[@abi.PReg]
  float_regs : Array[@abi.PReg]
  vector_regs : Array[@abi.PReg]
  callee_saved_int : Array[@abi.PReg]
  callee_saved_float : Array[@abi.PReg]

  // Block order for comparison (O(1) lookup)
  block_order : FixedArray[Int]

  // Reference to function for constraint lookups
  func : VCodeFunction
}

///|
/// Heap push into the allocator queue.
fn BacktrackingAllocator::queue_push(
  self : BacktrackingAllocator,
  bundle_id : Int,
  weight : Double,
  hint_preg : @abi.PReg?,
) -> Unit {
  let entry : QueueEntry = {
    bundle_id,
    weight,
    hint_preg,
    seq: self.queue_next_seq,
  }
  self.queue_next_seq = self.queue_next_seq + 1
  self.queue.push(entry)
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
pub fn BacktrackingAllocator::new(
  func : VCodeFunction,
  ranges : LiveRangeSet,
  bundles : BundleSet,
  int_regs : Array[@abi.PReg],
  float_regs : Array[@abi.PReg],
  vector_regs : Array[@abi.PReg],
  callee_saved_int : Array[@abi.PReg],
  callee_saved_float : Array[@abi.PReg],
) -> BacktrackingAllocator {
  {
    ranges,
    bundles,
    int_reg_allocs: {},
    float_reg_allocs: {},
    int_reg_bundles: {},
    float_reg_bundles: {},
    queue: [],
    queue_next_seq: 0,
    spillset_hints: Array::make(bundles.length(), None),
    int_regs,
    float_regs,
    vector_regs,
    callee_saved_int,
    callee_saved_float,
    block_order: ranges.block_order,
    func,
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
  let avail_idx : Set[Int] = Set::new()
  for r in avail_regs {
    avail_idx.add(r.index) |> ignore
  }

  // Count how often each fixed preg appears in uses.
  let counts : Map[Int, Int] = {}
  for range_id in bundle.range_ids {
    let range = self.ranges.get(range_id)
    for use_pos in range.uses {
      match use_pos.constraint {
        FixedReg(preg) =>
          if preg.class == bundle.reg_class && avail_idx.contains(preg.index) {
            let cur = match counts.get(preg.index) {
              Some(v) => v
              None => 0
            }
            counts.set(preg.index, cur + 1)
          }
        AnyReg => ()
      }
    }
  }
  let mut best : (@abi.PReg, Int)? = None
  for idx, cnt in counts {
    let preg : @abi.PReg = { index: idx, class: bundle.reg_class }
    match best {
      None => best = Some((preg, cnt))
      Some((bp, bc)) =>
        if cnt > bc || (cnt == bc && idx < bp.index) {
          best = Some((preg, cnt))
        }
    }
  }
  match best {
    Some((preg, _)) => Some(preg)
    None => None
  }
}

///|
/// Initialize the priority queue with all bundles
fn BacktrackingAllocator::init_queue(self : BacktrackingAllocator) -> Unit {
  self.queue = []
  self.queue_next_seq = 0
  // Pre-compute loop depths once (O(blocks + edges))
  let loop_depths = compute_loop_depths(self.func)
  for i in 0..<self.bundles.length() {
    let bundle = self.bundles.get(i)
    bundle.spill_weight = compute_spill_weight(bundle, self.ranges, loop_depths)
    self.queue.push({
      bundle_id: i,
      weight: bundle.spill_weight,
      hint_preg: self.constraint_hint_preg(bundle),
      seq: self.queue_next_seq,
    })
    self.queue_next_seq = self.queue_next_seq + 1
  }
  // Heapify (max-heap).
  let n = self.queue.length()
  if n <= 1 {
    return
  }
  let mut i = n / 2 - 1
  while i >= 0 {
    // Sift down from i.
    let mut p = i
    while true {
      let left = p * 2 + 1
      if left >= n {
        break
      }
      let right = left + 1
      let mut best = left
      if right < n && queue_entry_higher(self.queue[right], self.queue[left]) {
        best = right
      }
      if queue_entry_higher(self.queue[best], self.queue[p]) {
        let tmp = self.queue[p]
        self.queue[p] = self.queue[best]
        self.queue[best] = tmp
        p = best
      } else {
        break
      }
    }
    if i == 0 {
      break
    }
    i = i - 1
  }
}

///|
/// Get the occupancy map for a register class
fn BacktrackingAllocator::get_reg_allocs(
  self : BacktrackingAllocator,
  class : @abi.RegClass,
) -> Map[Int, Array[(Int, ProgPointRange)]] {
  match class {
    @abi.Int => self.int_reg_allocs
    @abi.Float32 | @abi.Float64 | @abi.Vector => self.float_reg_allocs
  }
}

///|
/// Get the bundle index map for a register class
fn BacktrackingAllocator::get_reg_bundles(
  self : BacktrackingAllocator,
  class : @abi.RegClass,
) -> Map[Int, Set[Int]] {
  match class {
    @abi.Int => self.int_reg_bundles
    @abi.Float32 | @abi.Float64 | @abi.Vector => self.float_reg_bundles
  }
}

///|
/// Get available registers for a bundle
fn BacktrackingAllocator::get_available_regs(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Array[@abi.PReg] {
  if bundle.crosses_call(self.ranges) {
    match bundle.reg_class {
      @abi.Int => self.callee_saved_int
      @abi.Float32 | @abi.Float64 => self.callee_saved_float
      // V8-V15 preservation is only guaranteed for the low 64 bits by AAPCS64.
      // Vector values that cross calls are handled by forced spilling earlier.
      @abi.Vector => []
    }
  } else {
    match bundle.reg_class {
      @abi.Int => self.int_regs
      @abi.Float32 | @abi.Float64 => self.float_regs
      @abi.Vector => self.vector_regs
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
  let allocs = self.get_reg_allocs(preg.class)
  let occupied = allocs.get(preg.index)
  match occupied {
    None => true // No allocations yet
    Some(ranges) => {
      // Check if any bundle range overlaps with occupied ranges
      for range_id in bundle.range_ids {
        let range = self.ranges.get(range_id)
        for span in range.ranges {
          for occ in ranges {
            if span.overlaps(occ.1, self.block_order) {
              return false
            }
          }
        }
      }
      true
    }
  }
}

///|
/// Record allocation of a register to a bundle
fn BacktrackingAllocator::record_allocation(
  self : BacktrackingAllocator,
  bundle : Bundle,
  preg : @abi.PReg,
) -> Unit {
  let allocs = self.get_reg_allocs(preg.class)
  if allocs.get(preg.index) is None {
    allocs.set(preg.index, [])
  }
  let occupied = allocs.get(preg.index).unwrap()
  for range_id in bundle.range_ids {
    let range = self.ranges.get(range_id)
    for span in range.ranges {
      occupied.push((bundle.id, span))
    }
    // Also update the LiveRange's allocation
    range.allocation = Reg(preg)
  }
  bundle.allocation = Reg(preg)

  // Update spillset hint (Cranelift-style): this helps split pieces prefer
  // the same preg, reducing move traffic and improving locality.
  let spillset_id = bundle.spillset_id
  if spillset_id >= 0 && spillset_id < self.spillset_hints.length() {
    self.spillset_hints[spillset_id] = Some(preg)
  }

  // Update bundle index for fast conflict lookup
  let bundle_index = self.get_reg_bundles(preg.class)
  if bundle_index.get(preg.index) is None {
    bundle_index.set(preg.index, Set::new())
  }
  bundle_index.get(preg.index).unwrap().add(bundle.id)
}

///|
/// Remove allocation of a bundle (for eviction)
fn BacktrackingAllocator::remove_allocation(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Unit {
  if bundle.allocation is Reg(preg) {
    let allocs = self.get_reg_allocs(preg.class)
    if allocs.get(preg.index) is Some(occupied) {
      // Remove ranges belonging to this bundle.
      let new_occupied : Array[(Int, ProgPointRange)] = []
      for occ in occupied {
        if occ.0 != bundle.id {
          new_occupied.push(occ)
        }
      }
      allocs.set(preg.index, new_occupied)
    }

    // Remove from bundle index
    let bundle_index = self.get_reg_bundles(preg.class)
    if bundle_index.get(preg.index) is Some(bundle_set) {
      bundle_set.remove(bundle.id)
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

  // Probe hint first if present and available.
  if hint_preg is Some(hint) {
    for preg in avail_regs {
      if preg.class == hint.class && preg.index == hint.index {
        if self.is_reg_free(preg, bundle) {
          return Some(preg)
        }
        break
      }
    }
  }

  // Try each available register (Cranelift-like offset scan to distribute contention).
  let n = avail_regs.length()
  if n == 0 {
    return None
  }
  let mut start_inst = 0
  let mut start_point : ProgPoint? = None
  for range_id in bundle.range_ids {
    let range = self.ranges.get(range_id)
    for span in range.ranges {
      let p = span.start
      match start_point {
        None => start_point = Some(p)
        Some(existing) =>
          if p.compare_with_order(existing, self.block_order) < 0 {
            start_point = Some(p)
          }
      }
    }
  }
  if start_point is Some(p) {
    start_inst = p.inst
  }
  // `ProgPoint.inst` may be -1 (block params). Ensure non-negative offset.
  let raw = bundle.id + start_inst
  let offset = (raw % n + n) % n
  for i in 0..<n {
    let preg = avail_regs[(offset + i) % n]
    if hint_preg is Some(hint) &&
      preg.class == hint.class &&
      preg.index == hint.index {
      continue
    }
    if self.is_reg_free(preg, bundle) {
      return Some(preg)
    }
  }
  None
}

///|
/// Find conflicting bundles for a given bundle and register
fn BacktrackingAllocator::find_conflicts(
  self : BacktrackingAllocator,
  bundle : Bundle,
  preg : @abi.PReg,
) -> Array[Int] {
  let conflicts : Array[Int] = []

  // Use bundle index for O(bundles_on_register) instead of O(all_bundles)
  let bundle_index = self.get_reg_bundles(preg.class)
  if bundle_index.get(preg.index) is Some(bundle_set) {
    for other_id in bundle_set {
      let other = self.bundles.get(other_id)
      if bundle.overlaps(other, self.ranges) {
        conflicts.push(other_id)
      }
    }
  }
  conflicts
}

///|
/// Try to evict lower-weight bundles to make room
/// Returns the register if eviction was successful
fn BacktrackingAllocator::try_evict(
  self : BacktrackingAllocator,
  bundle : Bundle,
  hint_preg : @abi.PReg?,
) -> @abi.PReg? {
  let avail_regs = self.get_available_regs(bundle)

  // Prefer hint preg when attempting eviction; it helps keep split pieces sticky.
  if hint_preg is Some(hint) {
    for preg in avail_regs {
      if preg.class == hint.class && preg.index == hint.index {
        let conflicts = self.find_conflicts(bundle, preg)
        if !conflicts.is_empty() {
          // (Continue with normal logic below by starting at this preg.)
          break
        }
      }
    }
  }
  let n = avail_regs.length()
  if n == 0 {
    return None
  }
  let offset = bundle.id % n
  for i in 0..<n {
    let preg = avail_regs[(offset + i) % n]
    if hint_preg is Some(hint) &&
      preg.class == hint.class &&
      preg.index == hint.index {
      // Keep hint preg as a preferred candidate but don't special-case it here;
      // the scan order already includes it.
      ()
    }
    let conflicts = self.find_conflicts(bundle, preg)
    if conflicts.is_empty() {
      continue // Should have been caught by try_allocate
    }

    // Check if all conflicts have lower weight and are not pinned
    let mut can_evict = true
    let mut total_conflict_weight = 0.0
    for conflict_id in conflicts {
      let conflict = self.bundles.get(conflict_id)
      // Never evict pinned bundles (e.g., function parameters)
      if conflict.is_pinned {
        can_evict = false
        break
      }
      if conflict.spill_weight >= bundle.spill_weight {
        can_evict = false
        break
      }
      total_conflict_weight += conflict.spill_weight
    }

    // Only evict if our weight is significantly higher
    if can_evict && bundle.spill_weight > total_conflict_weight {
      // Evict all conflicts
      for conflict_id in conflicts {
        let conflict = self.bundles.get(conflict_id)
        self.remove_allocation(conflict)
        // Re-add to queue with slightly lower weight
        let new_weight = conflict.spill_weight * 0.9
        conflict.spill_weight = new_weight
        self.queue_push(conflict_id, new_weight, None)
      }
      return Some(preg)
    }
  }
  None
}

///|
/// Find the first conflict point for a bundle on a specific physical register.
fn BacktrackingAllocator::find_first_conflict_point_for_preg(
  self : BacktrackingAllocator,
  bundle : Bundle,
  preg : @abi.PReg,
) -> ProgPoint? {
  let mut earliest_conflict : ProgPoint? = None
  let allocs = self.get_reg_allocs(preg.class)
  if allocs.get(preg.index) is Some(occupied) {
    for range_id in bundle.range_ids {
      let range = self.ranges.get(range_id)
      for span in range.ranges {
        for occ in occupied {
          if span.overlaps(occ.1, self.block_order) {
            // Find the overlap start point
            let conflict_start = if span.start.compare_with_order(
                occ.1.start,
                self.block_order,
              ) >
              0 {
              span.start
            } else {
              occ.1.start
            }
            match earliest_conflict {
              None => earliest_conflict = Some(conflict_start)
              Some(existing) =>
                if conflict_start.compare_with_order(existing, self.block_order) <
                  0 {
                  earliest_conflict = Some(conflict_start)
                }
            }
          }
        }
      }
    }
  }
  earliest_conflict
}

///|
/// Choose a split point and a reg hint (Cranelift-like):
/// - Try all available regs (hint-first if provided).
/// - Prefer lower maximum-conflict weight.
/// - Tie-break by later first-conflict point (larger conflict-free prefix).
fn BacktrackingAllocator::choose_split_option(
  self : BacktrackingAllocator,
  bundle : Bundle,
  hint_preg : @abi.PReg?,
) -> (ProgPoint, @abi.PReg)? {
  let avail_regs = self.get_available_regs(bundle)
  if avail_regs.is_empty() {
    return None
  }
  let mut best : (ProgPoint, @abi.PReg)? = None
  let mut best_cost : Double? = None
  fn consider(
    self : BacktrackingAllocator,
    bundle : Bundle,
    preg : @abi.PReg,
    best : (ProgPoint, @abi.PReg)?,
    best_cost : Double?,
  ) -> ((ProgPoint, @abi.PReg)?, Double?) {
    let conflicts = self.find_conflicts(bundle, preg)
    if conflicts.is_empty() {
      return (best, best_cost)
    }
    let point = self.find_first_conflict_point_for_preg(bundle, preg)
    if point is None {
      return (best, best_cost)
    }
    let split_point = point.unwrap()
    let mut cost = 0.0
    for conflict_id in conflicts {
      let b = self.bundles.get(conflict_id)
      // Treat pinned bundles as extremely expensive to conflict with.
      if b.is_pinned {
        cost = 1.0e100
        break
      }
      if b.spill_weight > cost {
        cost = b.spill_weight
      }
    }
    match (best, best_cost) {
      (None, None) => (Some((split_point, preg)), Some(cost))
      (Some((best_point, best_preg)), Some(best_cost_v)) =>
        if cost < best_cost_v {
          (Some((split_point, preg)), Some(cost))
        } else if cost == best_cost_v &&
          split_point.compare_with_order(best_point, self.block_order) > 0 {
          (Some((split_point, preg)), Some(cost))
        } else {
          (Some((best_point, best_preg)), Some(best_cost_v))
        }
      _ => (best, best_cost)
    }
  }

  // Hint-first.
  if hint_preg is Some(hint) {
    for preg in avail_regs {
      if preg.class == hint.class && preg.index == hint.index {
        let (b, c) = consider(self, bundle, preg, best, best_cost)
        best = b
        best_cost = c
        break
      }
    }
  }

  // Offset scan through the remaining regs.
  let n = avail_regs.length()
  let offset = bundle.id % n
  for i in 0..<n {
    let preg = avail_regs[(offset + i) % n]
    if hint_preg is Some(hint) &&
      preg.class == hint.class &&
      preg.index == hint.index {
      continue
    }
    let (b, c) = consider(self, bundle, preg, best, best_cost)
    best = b
    best_cost = c
  }
  best
}

///|
/// Split a bundle at conflict points
fn BacktrackingAllocator::split_bundle(
  self : BacktrackingAllocator,
  bundle : Bundle,
  hint_preg : @abi.PReg?,
) -> Unit {
  // Try to find a split point (and a reg hint) to split at.
  let split_opt = self.choose_split_option(bundle, hint_preg)
  match split_opt {
    Some((split_point, split_hint_reg)) => {
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
        let slot = spill_bundle.slot
        bundle.allocation = Spill(slot)
        for range_id in bundle.range_ids {
          let range = self.ranges.get(range_id)
          range.allocation = Spill(slot)
        }
        return
      }

      // Create new bundles with reduced weight
      let new_weight = bundle.spill_weight * 0.9

      // Before bundle
      let before_bundle = Bundle::new(
        self.bundles.bundles.length(),
        bundle.reg_class,
      )
      before_bundle.spill_weight = new_weight
      before_bundle.spill_bundle_id = spill_bundle.id
      before_bundle.spillset_id = bundle.spillset_id
      for range_id in before_ranges {
        before_bundle.add_range(range_id)
        self.ranges.get(range_id).bundle_id = before_bundle.id
      }
      self.bundles.add_bundle(before_bundle)
      spill_bundle.add_bundle(before_bundle.id)
      self.queue_push(before_bundle.id, new_weight, Some(split_hint_reg))

      // After bundle
      let after_bundle = Bundle::new(
        self.bundles.bundles.length(),
        bundle.reg_class,
      )
      after_bundle.spill_weight = new_weight
      after_bundle.spill_bundle_id = spill_bundle.id
      after_bundle.spillset_id = bundle.spillset_id
      for range_id in after_ranges {
        after_bundle.add_range(range_id)
        self.ranges.get(range_id).bundle_id = after_bundle.id
      }
      self.bundles.add_bundle(after_bundle)
      spill_bundle.add_bundle(after_bundle.id)
      self.queue_push(after_bundle.id, new_weight, Some(split_hint_reg))

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
/// Main allocation loop
pub fn BacktrackingAllocator::allocate(self : BacktrackingAllocator) -> Unit {
  self.init_queue()

  // Track processed bundles to avoid infinite loops
  let processed : Set[Int] = Set::new()
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
      None => self.constraint_hint_preg(bundle)
    }

    // Skip if already allocated
    if bundle.allocation is Reg(_) || bundle.allocation is Spill(_) {
      continue
    }

    // Vector values live across calls must spill.
    if bundle.reg_class is @abi.Vector && bundle.crosses_call(self.ranges) {
      self.force_spill_bundle(bundle)
      processed.add(entry.bundle_id)
      continue
    }

    // Cranelift-style conservative call clobbers for C calls: treat all V0-V31 as clobbered.
    // To be safe, spill any float values that cross a C call.
    if (bundle.reg_class is @abi.Float32 || bundle.reg_class is @abi.Float64) &&
      bundle.crosses_c_call(self.ranges) {
      self.force_spill_bundle(bundle)
      processed.add(entry.bundle_id)
      continue
    }

    // Try to allocate a register
    if self.try_allocate(bundle, hint_preg) is Some(preg) {
      self.record_allocation(bundle, preg)
      processed.add(entry.bundle_id)
      continue
    }

    // try_allocate may have decided to spill
    if bundle.allocation is Spill(_) {
      processed.add(entry.bundle_id)
      continue
    }

    // Try to evict lower-weight bundles
    if self.try_evict(bundle, hint_preg) is Some(preg) {
      self.record_allocation(bundle, preg)
      processed.add(entry.bundle_id)
      continue
    }

    // Split (spill) the bundle
    self.split_bundle(bundle, hint_preg)
    processed.add(entry.bundle_id)
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
    inst_edits: {},
  }

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
      }
      Spill(slot) => result.spill_slots.set(range.vreg.id, slot)
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
        if constraint is @abi.FixedReg(required_preg) {
          let use_reg = inst.uses[i]
          if use_reg is @abi.Virtual(vreg) {
            // Check if already allocated to the required register
            match result.assignments.get(vreg.id) {
              Some(assigned_preg) =>
                if assigned_preg.index != required_preg.index {
                  // Need to move from assigned to required
                  edits.before.push({
                    from: Reg(assigned_preg),
                    to: Reg(required_preg),
                    class: vreg.class,
                  })
                }
              // If already at required_preg, no move needed
              None =>
                // Spilled: need to reload to the required register
                if result.spill_slots.get(vreg.id) is Some(slot) {
                  edits.before.push({
                    from: Spill(slot),
                    to: Reg(required_preg),
                    class: vreg.class,
                  })
                }
            }
          }
        }
      }

      // Process def constraints (moves after the instruction)
      for i, constraint in inst.def_constraints {
        if constraint is @abi.FixedReg(required_preg) {
          let def = inst.defs[i]
          if def.reg is @abi.Virtual(vreg) {
            // Check if already allocated to the required register
            match result.assignments.get(vreg.id) {
              Some(assigned_preg) =>
                if assigned_preg.index != required_preg.index {
                  // Need to move from required to assigned
                  // (the instruction produces in required_preg, we need to move to assigned)
                  edits.after.push({
                    from: Reg(required_preg),
                    to: Reg(assigned_preg),
                    class: vreg.class,
                  })
                }
              None =>
                // Spilled: need to store from required register to spill slot
                if result.spill_slots.get(vreg.id) is Some(slot) {
                  edits.after.push({
                    from: Reg(required_preg),
                    to: Spill(slot),
                    class: vreg.class,
                  })
                }
            }
          }
        }
      }

      // Store edits if any
      if !edits.before.is_empty() || !edits.after.is_empty() {
        result.inst_edits.set((block_idx, inst_idx), edits)
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
  // Per spill-slot (spill-bundle slot) we record the union of live ranges
  // (as ProgPointRange spans) for all vregs assigned to that spill slot.
  struct SpillSetInfo {
    old_slot : Int
    reg_class : @abi.RegClass
    spans : Array[ProgPointRange]
    start : ProgPoint
  }
  struct AssignedSlot {
    start : Int
    spans : Array[ProgPointRange]
  }
  fn slots_used(cls : @abi.RegClass) -> Int {
    match cls {
      @abi.Vector => 2
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
      if !spans_overlap(ss.spans, slot.spans, self.ranges.block_order) {
        slot_remap.set(ss.old_slot, slot.start)
        // Extend occupancy for future overlap checks.
        for span in ss.spans {
          slot.spans.push(span)
        }
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
    pool.push({ start: new_slot, spans: new_spans })
    slot_remap.set(ss.old_slot, new_slot)
  }

  // 4) Rewrite all spill-slot references (spill map + constraint edits).
  for vreg_id, old_slot in result.spill_slots {
    match slot_remap.get(old_slot) {
      Some(new_slot) => result.spill_slots.set(vreg_id, new_slot)
      None => ()
    }
  }
  for _key, edits in result.inst_edits {
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
  let n = ranges.length()
  let uf = UnionFind::new(n)

  // Helper to try merging two ranges
  fn try_merge(
    uf : UnionFind,
    a : Int,
    b : Int,
    ranges : LiveRangeSet,
  ) -> Bool {
    if a < 0 || b < 0 || a >= ranges.length() || b >= ranges.length() {
      return false
    }

    // Already in same set
    if uf.same_set(a, b) {
      return true
    }
    let range_a = ranges.get(a)
    let range_b = ranges.get(b)

    // Must be same register class
    if not(reg_class_compatible(range_a.vreg.class, range_b.vreg.class)) {
      return false
    }

    // Check for overlap within potential merged bundle
    let set_a = uf.get_set(a)
    let set_b = uf.get_set(b)
    for idx_a in set_a {
      let r_a = ranges.get(idx_a)
      for idx_b in set_b {
        let r_b = ranges.get(idx_b)
        if r_a.overlaps(r_b, ranges.block_order) {
          return false
        }
      }
    }
    uf.union(a, b) |> ignore
    true
  }

  // 1. Merge across Move instructions
  for block in func.blocks {
    for inst in block.insts {
      if inst.opcode is @instr.Move &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 {
        // Get source and destination vregs
        let src_vreg_id = match inst.uses[0] {
          @abi.Virtual(vreg) => Some(vreg.id)
          _ => None
        }
        let dst_vreg_id = match inst.defs[0].reg {
          @abi.Virtual(vreg) => Some(vreg.id)
          _ => None
        }
        if (src_vreg_id, dst_vreg_id) is (Some(src_id), Some(dst_id)) {
          // Find range indices
          if ranges.vreg_to_range.get(src_id) is Some(src_idx) {
            if ranges.vreg_to_range.get(dst_id) is Some(dst_idx) {
              try_merge(uf, src_idx, dst_idx, ranges) |> ignore
            }
          }
        }
      }
    }
  }

  // 2. Merge across block arguments (SSA phi-like connections)
  // For each Jump(target, args), the i-th arg corresponds to the i-th block param.
  // Coalescing these bundles avoids edge moves and preserves SSA semantics.
  let block_idx : Map[Int, Int] = {}
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  for pred_block in func.blocks {
    if pred_block.terminator is Some(Jump(target, args)) {
      let target_block = match block_idx.get(target) {
        Some(idx) => func.blocks[idx]
        None => continue
      }
      if target_block.params.is_empty() {
        continue
      }
      // Merge each param with its incoming argument vreg.
      for i, param in target_block.params {
        if i >= args.length() {
          break
        }
        match args[i] {
          @abi.Virtual(arg_vreg) =>
            if ranges.vreg_to_range.get(param.id) is Some(param_idx) &&
              ranges.vreg_to_range.get(arg_vreg.id) is Some(arg_idx) {
              try_merge(uf, param_idx, arg_idx, ranges) |> ignore
            }
          _ => ()
        }
      }
    }
  }

  // Build final bundles from union-find sets
  let result = BundleSet::new()
  let sets = uf.get_all_sets()
  for set_idx, members in sets {
    ignore(set_idx)
    if members.is_empty() {
      continue
    }

    // Get register class from first member
    let first_range = ranges.get(members[0])
    let bundle = Bundle::new(result.bundles.length(), first_range.vreg.class)
    for range_idx in members {
      bundle.add_range(range_idx)
      ranges.get(range_idx).bundle_id = bundle.id
    }
    result.add_bundle(bundle)
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
) -> Unit {
  let isa = @isa.ISA::current()
  let vmctx_preg = isa.wasm_vmctx_arg_preg()
  let user_arg_gprs = isa.wasm_user_arg_gprs()
  let arg_fprs = isa.wasm_arg_fprs()
  let mut int_idx = 0
  let mut float_idx = 0
  let mut callee_saved_int_idx = 0
  let mut callee_saved_float_idx = 0
  for param in self.func.params {
    // Determine which ABI register this param comes in
    let (preg_opt, is_int) : (@abi.PReg?, Bool) = match param.class {
      @abi.Int =>
        if int_idx == 0 {
          // First integer argument is always vmctx in the internal Wasm ABI.
          (Some(vmctx_preg), true)
        } else if int_idx - 1 < user_arg_gprs.length() {
          (Some(user_arg_gprs[int_idx - 1]), true)
        } else {
          (None, true) // Stack param
        }
      @abi.Float32 | @abi.Float64 | @abi.Vector =>
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

    // Skip stack params
    guard preg_opt is Some(preg) else { continue }

    // Find the LiveRange for this param and get its bundle
    let range = self.ranges.get_by_vreg(param.id)
    if range is Some(lr) && lr.bundle_id >= 0 {
      let bundle = self.bundles.bundles[lr.bundle_id]
      // If the param's bundle crosses a call (even if the param itself doesn't),
      // the bundle must not be pinned to a caller-saved arg register.
      //
      // This can happen when block params / copies coalesce with function params
      // and the later ranges in the same bundle are live across a call.
      if bundle.crosses_call(self.ranges) {
        // For 128-bit SIMD vectors, AAPCS64 only guarantees preserving the low
        // 64 bits of V8-V15 across calls. To keep semantics correct, force spill.
        if !is_int && param.class is @abi.Vector {
          self.force_spill_bundle(bundle)
          bundle.is_pinned = true
          continue
        }

        // Cranelift-style conservative clobbers for C calls: treat all V0-V31 as clobbered.
        // Any float value that crosses a C call must spill.
        if !is_int && bundle.crosses_c_call(self.ranges) {
          self.force_spill_bundle(bundle)
          bundle.is_pinned = true
          continue
        }

        // Otherwise, allocate to callee-saved registers so the bundle can
        // survive Wasm-to-Wasm calls safely.
        let callee_saved_preg = if is_int {
          if callee_saved_int_idx < self.callee_saved_int.length() {
            let p = self.callee_saved_int[callee_saved_int_idx]
            callee_saved_int_idx = callee_saved_int_idx + 1
            Some(p)
          } else {
            None
          }
        } else if callee_saved_float_idx < self.callee_saved_float.length() {
          let p = self.callee_saved_float[callee_saved_float_idx]
          callee_saved_float_idx = callee_saved_float_idx + 1
          Some(p)
        } else {
          None
        }
        if callee_saved_preg is Some(cs_preg) {
          self.record_allocation(bundle, cs_preg)
          bundle.is_pinned = true // Prevent eviction of param bundles
        }
        continue
      }

      // Normal case: pin param bundle to its incoming ABI register.
      self.record_allocation(bundle, preg)
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
) -> RegAllocResult {
  // Phase 2: Build LiveRanges
  let ranges = build_live_ranges(func, liveness)

  // Phase 3: Build Bundles with merging
  let bundles = build_bundles_with_merging(func, ranges)

  // Phase 4: Allocate
  let allocator = BacktrackingAllocator::new(
    func, ranges, bundles, int_regs, float_regs, vector_regs, callee_saved_int, callee_saved_float,
  )

  // Pre-assign function parameters to ABI registers (before main allocation)
  allocator.preassign_params()
  allocator.allocate()

  // Generate result
  allocator.generate_result()
}
