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
pub(all) struct BacktrackingAllocator {
  // Core data
  ranges : LiveRangeSet
  bundles : BundleSet

  // Physical register occupancy: preg.index -> list of occupied ranges
  int_reg_allocs : Map[Int, Array[ProgPointRange]]
  float_reg_allocs : Map[Int, Array[ProgPointRange]]

  // Priority queue of bundles to process
  mut queue : Array[QueueEntry]

  // Configuration
  int_regs : Array[@abi.PReg]
  float_regs : Array[@abi.PReg]
  callee_saved_int : Array[@abi.PReg]
  callee_saved_float : Array[@abi.PReg]

  // Block order for comparison
  block_order : Map[Int, Int]

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
  callee_saved_int : Array[@abi.PReg],
  callee_saved_float : Array[@abi.PReg],
) -> BacktrackingAllocator {
  {
    ranges,
    bundles,
    int_reg_allocs: {},
    float_reg_allocs: {},
    queue: [],
    int_regs,
    float_regs,
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
  for i in 0..<self.bundles.length() {
    let bundle = self.bundles.get(i)
    bundle.spill_weight = compute_spill_weight(bundle, self.ranges, self.func)
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
/// Get available registers for a bundle
fn BacktrackingAllocator::get_available_regs(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Array[@abi.PReg] {
  if bundle.crosses_call(self.ranges) {
    match bundle.reg_class {
      @abi.Int => self.callee_saved_int
      @abi.Float32 | @abi.Float64 | @abi.Vector => self.callee_saved_float
    }
  } else {
    match bundle.reg_class {
      @abi.Int => self.int_regs
      @abi.Float32 | @abi.Float64 | @abi.Vector => self.float_regs
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
) -> @abi.PReg? {
  // First check for fixed constraint
  if bundle.get_fixed_reg(self.ranges) is Some(fixed_preg) {
    if self.is_reg_free(fixed_preg, bundle) {
      return Some(fixed_preg)
    }
    return None // Must use fixed reg but it's occupied
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

  // Find all bundles allocated to this preg that overlap
  for i in 0..<self.bundles.length() {
    let other = self.bundles.get(i)
    if other.allocation is Reg(other_preg) &&
      other_preg.index == preg.index &&
      bundle.overlaps(other, self.ranges) {
      conflicts.push(i)
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

    // Check if all conflicts have lower weight
    let mut can_evict = true
    let mut total_conflict_weight = 0.0
    for conflict_id in conflicts {
      let conflict = self.bundles.get(conflict_id)
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
/// Split a bundle at conflict points
fn BacktrackingAllocator::split_bundle(
  self : BacktrackingAllocator,
  bundle : Bundle,
) -> Unit {
  // Simple splitting strategy: spill the entire bundle
  // A more sophisticated implementation would split at conflict points

  // Get or create spill bundle
  let spill_bundle = self.bundles.get_or_create_spill_bundle(bundle)
  let slot = spill_bundle.slot

  // Mark as spilled
  bundle.allocation = Spill(slot)
  for range_id in bundle.range_ids {
    let range = self.ranges.get(range_id)
    range.allocation = Spill(slot)
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

    // Try to allocate a register
    if self.try_allocate(bundle) is Some(preg) {
      self.record_allocation(bundle, preg)
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
/// Generate allocation result compatible with existing code
pub fn BacktrackingAllocator::generate_result(
  self : BacktrackingAllocator,
) -> RegAllocResult {
  let result : RegAllocResult = {
    assignments: {},
    spill_slots: {},
    num_spill_slots: self.bundles.next_spill_slot,
    spills: [],
    reloads: [],
    inst_edits: {},
  }

  // Collect assignments from LiveRanges
  for i in 0..<self.ranges.length() {
    let range = self.ranges.get(i)
    match range.allocation {
      Reg(preg) => result.assignments.set(range.vreg.id, preg)
      Spill(slot) => result.spill_slots.set(range.vreg.id, slot)
      Unallocated => () // Should not happen after allocation
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
  // For each block with parameters, try to merge with the corresponding
  // arguments from predecessor branches
  for block in func.blocks {
    if block.params.is_empty() {
      continue
    }

    // Find predecessors and their branch arguments
    for pred_block in func.blocks {
      if pred_block.terminator is Some(term) {
        match term {
          Jump(target) =>
            if target == block.id {
              // This predecessor jumps to our block
              // Block params should be populated from predecessor's values
              // In current VCode, this is handled via moves before the jump
              // So we already handle this via Move instruction merging
            }
          Branch(_, then_b, else_b) =>
            if then_b == block.id || else_b == block.id {
              // Similar handling
            }
          BranchCmp(_, _, _, _, then_b, else_b) =>
            if then_b == block.id || else_b == block.id {
              // Similar handling
            }
          BranchCmpImm(_, _, _, _, then_b, else_b) =>
            if then_b == block.id || else_b == block.id {
              // Similar handling
            }
          BranchZero(_, _, _, then_b, else_b) =>
            if then_b == block.id || else_b == block.id {
              // Similar handling
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
/// Main entry point for backtracking allocation
pub fn allocate_backtracking(
  func : VCodeFunction,
  liveness : LivenessResult,
  int_regs : Array[@abi.PReg],
  float_regs : Array[@abi.PReg],
  callee_saved_int : Array[@abi.PReg],
  callee_saved_float : Array[@abi.PReg],
) -> RegAllocResult {
  // Phase 2: Build LiveRanges
  let ranges = build_live_ranges(func, liveness)

  // Phase 3: Build Bundles with merging
  let bundles = build_bundles_with_merging(func, ranges)

  // Phase 4: Allocate
  let allocator = BacktrackingAllocator::new(
    func, ranges, bundles, int_regs, float_regs, callee_saved_int, callee_saved_float,
  )
  allocator.allocate()

  // Generate result
  allocator.generate_result()
}
