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
struct QueueEntry {
  bundle_id : Int
  weight : Double
} derive(Eq)

///|
/// The backtracking register allocator
struct BacktrackingAllocator {
  // Core data
  ranges : LiveRangeSet
  bundles : BundleSet

  // Physical register occupancy: preg.index -> list of occupied ranges
  int_reg_allocs : Map[Int, Array[ProgPointRange]]
  float_reg_allocs : Map[Int, Array[ProgPointRange]]

  // Index: preg.index -> set of bundle IDs allocated to this register
  // Used for fast conflict lookup in find_conflicts
  int_reg_bundles : Map[Int, Set[Int]]
  float_reg_bundles : Map[Int, Set[Int]]

  // Priority queue of bundles to process
  mut queue : Array[QueueEntry]

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
/// Initialize the priority queue with all bundles
fn BacktrackingAllocator::init_queue(self : BacktrackingAllocator) -> Unit {
  self.queue = []
  // Pre-compute loop depths once (O(blocks + edges))
  let loop_depths = compute_loop_depths(self.func)
  for i in 0..<self.bundles.length() {
    let bundle = self.bundles.get(i)
    bundle.spill_weight = compute_spill_weight(bundle, self.ranges, loop_depths)
    self.queue.push({ bundle_id: i, weight: bundle.spill_weight })
  }
  // Sort by weight descending (highest priority first)
  self.queue.sort_by(fn(a, b) {
    if a.weight > b.weight {
      -1
    } else if a.weight < b.weight {
      1
    } else {
      0
    }
  })
}

///|
/// Get the occupancy map for a register class
fn BacktrackingAllocator::get_reg_allocs(
  self : BacktrackingAllocator,
  class : @abi.RegClass,
) -> Map[Int, Array[ProgPointRange]] {
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
            if span.overlaps(occ, self.block_order) {
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
      occupied.push(span)
    }
    // Also update the LiveRange's allocation
    range.allocation = Reg(preg)
  }
  bundle.allocation = Reg(preg)

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
      // Remove ranges belonging to this bundle
      let new_occupied : Array[ProgPointRange] = []
      for occ in occupied {
        let mut belongs_to_bundle = false
        for range_id in bundle.range_ids {
          let range = self.ranges.get(range_id)
          for span in range.ranges {
            if span.start.block == occ.start.block &&
              span.start.inst == occ.start.inst &&
              span.end.block == occ.end.block &&
              span.end.inst == occ.end.inst {
              belongs_to_bundle = true
              break
            }
          }
          if belongs_to_bundle {
            break
          }
        }
        if !belongs_to_bundle {
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
/// Check if a register is callee-saved
fn BacktrackingAllocator::is_callee_saved(
  self : BacktrackingAllocator,
  preg : @abi.PReg,
) -> Bool {
  match preg.class {
    @abi.Int =>
      for cs in self.callee_saved_int {
        if cs.index == preg.index {
          return true
        }
      }
    @abi.Float32 | @abi.Float64 =>
      for cs in self.callee_saved_float {
        if cs.index == preg.index {
          return true
        }
      }
    // AAPCS64 only guarantees preserving the low 64 bits of V8-V15.
    // Treat vectors as never callee-saved.
    @abi.Vector => ()
  }
  false
}

///|
/// Try to allocate a register for a bundle
/// Returns the allocated register if successful
fn BacktrackingAllocator::try_allocate(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> @abi.PReg? {
  // Check if bundle crosses a call - if so, need special handling
  let crosses_call = bundle.crosses_call(self.ranges)

  // Check for fixed constraint
  if bundle.get_fixed_reg(self.ranges) is Some(fixed_preg) {
    // If bundle crosses a call and the fixed register is caller-saved,
    // we should NOT allocate to the fixed register. Instead, allocate to
    // a callee-saved register and let process_constraints insert the move.
    if crosses_call && not(self.is_callee_saved(fixed_preg)) {
      // Fall through to normal allocation (will use callee-saved regs)
      ()
    } else {
      if self.is_reg_free(fixed_preg, bundle) {
        return Some(fixed_preg)
      }
      return None // Must use fixed reg but it's occupied
    }
  }

  // Try each available register
  let avail_regs = self.get_available_regs(bundle)
  for preg in avail_regs {
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
) -> @abi.PReg? {
  let avail_regs = self.get_available_regs(bundle)
  for preg in avail_regs {
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
        self.queue.push({ bundle_id: conflict_id, weight: new_weight })
      }
      return Some(preg)
    }
  }
  None
}

///|
/// Find the first conflict point for a bundle
fn BacktrackingAllocator::find_first_conflict_point(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> ProgPoint? {
  let avail_regs = self.get_available_regs(bundle)
  let mut earliest_conflict : ProgPoint? = None
  for preg in avail_regs {
    let allocs = self.get_reg_allocs(preg.class)
    if allocs.get(preg.index) is Some(occupied) {
      for range_id in bundle.range_ids {
        let range = self.ranges.get(range_id)
        for span in range.ranges {
          for occ in occupied {
            if span.overlaps(occ, self.block_order) {
              // Find the overlap start point
              let conflict_start = if span.start.compare_with_order(
                  occ.start,
                  self.block_order,
                ) >
                0 {
                span.start
              } else {
                occ.start
              }
              match earliest_conflict {
                None => earliest_conflict = Some(conflict_start)
                Some(existing) =>
                  if conflict_start.compare_with_order(
                      existing,
                      self.block_order,
                    ) <
                    0 {
                    earliest_conflict = Some(conflict_start)
                  }
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
/// Split a bundle at conflict points
fn BacktrackingAllocator::split_bundle(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Unit {
  // Try to find a conflict point to split at
  let conflict_point = self.find_first_conflict_point(bundle)
  match conflict_point {
    Some(split_point) => {
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
      for range_id in before_ranges {
        before_bundle.add_range(range_id)
        self.ranges.get(range_id).bundle_id = before_bundle.id
      }
      self.bundles.add_bundle(before_bundle)
      spill_bundle.add_bundle(before_bundle.id)
      self.queue.push({ bundle_id: before_bundle.id, weight: new_weight })

      // After bundle
      let after_bundle = Bundle::new(
        self.bundles.bundles.length(),
        bundle.reg_class,
      )
      after_bundle.spill_weight = new_weight
      after_bundle.spill_bundle_id = spill_bundle.id
      for range_id in after_ranges {
        after_bundle.add_range(range_id)
        self.ranges.get(range_id).bundle_id = after_bundle.id
      }
      self.bundles.add_bundle(after_bundle)
      spill_bundle.add_bundle(after_bundle.id)
      self.queue.push({ bundle_id: after_bundle.id, weight: new_weight })

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
    let entry = self.queue.remove(0)
    let bundle = self.bundles.get(entry.bundle_id)

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
    if self.try_allocate(bundle) is Some(preg) {
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
    if self.try_evict(bundle) is Some(preg) {
      self.record_allocation(bundle, preg)
      processed.add(entry.bundle_id)
      continue
    }

    // Split (spill) the bundle
    self.split_bundle(bundle)
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
                    from: assigned_preg,
                    to: required_preg,
                    class: vreg.class,
                  })
                }
              // If already at required_preg, no move needed
              None =>
                // Spilled: need to reload to the required register
                if result.spill_slots.get(vreg.id) is Some(slot) {
                  // Encode spill slot as negative index in 'from'
                  // The emit phase will interpret this as a reload
                  let spilled_preg = @abi.PReg::spilled(slot, vreg.class)
                  edits.before.push({
                    from: spilled_preg,
                    to: required_preg,
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
                    from: required_preg,
                    to: assigned_preg,
                    class: vreg.class,
                  })
                }
              None =>
                // Spilled: need to store from required register to spill slot
                if result.spill_slots.get(vreg.id) is Some(slot) {
                  let spilled_preg = @abi.PReg::spilled(slot, vreg.class)
                  edits.after.push({
                    from: required_preg,
                    to: spilled_preg,
                    class: vreg.class,
                  })
                }
            }
          }
        }
      }

      // Store edits if any
      if not(edits.before.is_empty()) || not(edits.after.is_empty()) {
        result.inst_edits.set((block_idx, inst_idx), edits)
      }
    }
  }
  result
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
  let max_int_params = @abi.MAX_REG_PARAMS // 8
  let max_float_params = @abi.MAX_FLOAT_REG_PARAMS // 8
  let mut int_idx = 0
  let mut float_idx = 0
  let mut callee_saved_int_idx = 0
  let mut callee_saved_float_idx = 0
  for param in self.func.params {
    // Determine which ABI register this param comes in
    let (preg_opt, is_int) : (@abi.PReg?, Bool) = match param.class {
      @abi.Int =>
        if int_idx < max_int_params {
          (Some(@abi.PReg::{ index: int_idx, class: @abi.Int }), true)
        } else {
          (None, true) // Stack param
        }
      @abi.Float32 | @abi.Float64 | @abi.Vector =>
        if float_idx < max_float_params {
          (Some(@abi.PReg::{ index: float_idx, class: param.class }), false)
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
