// Ion-Style Bundle Data Structures
// Bundles group related LiveRanges for coalescing and allocation.

///|
/// A Bundle groups related LiveRanges that should ideally be allocated
/// to the same physical register. Bundles are formed by merging LiveRanges
/// connected by Move instructions, block arguments, or tied operands.
struct Bundle {
  id : Int
  range_ids : Array[Int] // Indices into LiveRangeSet
  mut spill_weight : Double // Priority for allocation (higher = more important)
  mut spill_bundle_id : Int // SpillBundle ID for split bundles (-1 if none)
  mut allocation : Allocation // Current allocation
  reg_class : @abi.RegClass // Register class for this bundle
  mut is_pinned : Bool // If true, cannot be evicted (e.g., function parameters)
}

///|
pub fn Bundle::new(id : Int, reg_class : @abi.RegClass) -> Bundle {
  {
    id,
    range_ids: [],
    spill_weight: 0.0,
    spill_bundle_id: -1,
    allocation: Unallocated,
    reg_class,
    is_pinned: false,
  }
}

///|
/// Add a LiveRange to this bundle
fn Bundle::add_range(self : Bundle, range_id : Int) -> Unit {
  self.range_ids.push(range_id)
}

///|
/// Check if this bundle contains a specific LiveRange
pub fn Bundle::contains_range(self : Bundle, range_id : Int) -> Bool {
  for id in self.range_ids {
    if id == range_id {
      return true
    }
  }
  false
}

///|
/// Check if this bundle overlaps with another bundle
pub fn Bundle::overlaps(
  self : Bundle,
  other : Bundle,
  ranges : LiveRangeSet,
) -> Bool {
  for self_range_id in self.range_ids {
    let self_range = ranges.get(self_range_id)
    for other_range_id in other.range_ids {
      let other_range = ranges.get(other_range_id)
      if self_range.overlaps(other_range, ranges.block_order) {
        return true
      }
    }
  }
  false
}

///|
/// Get total length of all ranges in this bundle
pub fn Bundle::total_length(self : Bundle, ranges : LiveRangeSet) -> Int {
  let mut total = 0
  for range_id in self.range_ids {
    total += ranges.get(range_id).total_length()
  }
  if total <= 0 {
    1
  } else {
    total
  }
}

///|
/// Check if this bundle has any fixed register constraint
pub fn Bundle::has_fixed_constraint(
  self : Bundle,
  ranges : LiveRangeSet,
) -> Bool {
  for range_id in self.range_ids {
    if ranges.get(range_id).has_fixed_constraint() {
      return true
    }
  }
  false
}

///|
/// Get the fixed register if all ranges in bundle require same fixed reg
pub fn Bundle::get_fixed_reg(
  self : Bundle,
  ranges : LiveRangeSet,
) -> @abi.PReg? {
  let mut fixed : @abi.PReg? = None
  for range_id in self.range_ids {
    let range_fixed = ranges.get(range_id).get_fixed_reg()
    match (fixed, range_fixed) {
      (None, Some(preg)) => fixed = Some(preg)
      (Some(existing), Some(preg)) =>
        if existing.index != preg.index {
          return None // Conflicting
        }
      _ => ()
    }
  }
  fixed
}

///|
/// Check if any range in this bundle crosses a function call
pub fn Bundle::crosses_call(self : Bundle, ranges : LiveRangeSet) -> Bool {
  for range_id in self.range_ids {
    if ranges.get(range_id).crosses_call {
      return true
    }
  }
  false
}

///|
/// Check if any range in this bundle crosses a Wasm call
pub fn Bundle::crosses_wasm_call(self : Bundle, ranges : LiveRangeSet) -> Bool {
  for range_id in self.range_ids {
    if ranges.get(range_id).crosses_wasm_call {
      return true
    }
  }
  false
}

///|
/// Check if any range in this bundle crosses a C call
pub fn Bundle::crosses_c_call(self : Bundle, ranges : LiveRangeSet) -> Bool {
  for range_id in self.range_ids {
    if ranges.get(range_id).crosses_c_call {
      return true
    }
  }
  false
}

///|
pub fn Bundle::to_string(self : Bundle, _ranges : LiveRangeSet) -> String {
  let mut result = "Bundle\{self.id} (\{self.reg_class}): ["
  for i, range_id in self.range_ids {
    if i > 0 {
      result = result + ", "
    }
    result = result + "LR\{range_id}"
  }
  result = result + "] weight=\{self.spill_weight} -> \{self.allocation}"
  result
}

///|
/// A SpillBundle tracks a shared spill slot for split bundles.
/// When a bundle is split, both parts share the same SpillBundle
/// so they use the same stack slot.
struct SpillBundle {
  id : Int
  slot : Int // Stack slot index
  bundle_ids : Array[Int] // Bundle IDs that share this spill slot
}

///|
pub fn SpillBundle::new(id : Int, slot : Int) -> SpillBundle {
  { id, slot, bundle_ids: [] }
}

///|
/// Add a bundle to this spill bundle
fn SpillBundle::add_bundle(self : SpillBundle, bundle_id : Int) -> Unit {
  self.bundle_ids.push(bundle_id)
}

///|
/// Collection of Bundles
struct BundleSet {
  bundles : Array[Bundle]
  spill_bundles : Array[SpillBundle]
  mut next_spill_slot : Int
}

///|
pub fn BundleSet::new() -> BundleSet {
  { bundles: [], spill_bundles: [], next_spill_slot: 0 }
}

///|
/// Add a new bundle
fn BundleSet::add_bundle(self : BundleSet, bundle : Bundle) -> Unit {
  self.bundles.push(bundle)
}

///|
/// Get bundle by ID
pub fn BundleSet::get(self : BundleSet, id : Int) -> Bundle {
  self.bundles[id]
}

///|
/// Get number of bundles
pub fn BundleSet::length(self : BundleSet) -> Int {
  self.bundles.length()
}

///|
/// Allocate a new spill slot and create SpillBundle
fn BundleSet::new_spill_bundle(
  self : BundleSet,
  reg_class : @abi.RegClass,
) -> SpillBundle {
  let id = self.spill_bundles.length()

  // Spill slots are counted in 8-byte units.
  // For 128-bit vectors, reserve 16 bytes and ensure 16-byte alignment.
  let (slot, slots_used) = match reg_class {
    @abi.Vector => {
      if self.next_spill_slot % 2 != 0 {
        self.next_spill_slot += 1
      }
      (self.next_spill_slot, 2)
    }
    _ => (self.next_spill_slot, 1)
  }
  self.next_spill_slot += slots_used
  let spill_bundle = SpillBundle::new(id, slot)
  self.spill_bundles.push(spill_bundle)
  spill_bundle
}

///|
/// Get or create SpillBundle for a bundle
fn BundleSet::get_or_create_spill_bundle(
  self : BundleSet,
  bundle : Bundle,
) -> SpillBundle {
  if bundle.spill_bundle_id >= 0 {
    self.spill_bundles[bundle.spill_bundle_id]
  } else {
    let spill_bundle = self.new_spill_bundle(bundle.reg_class)
    bundle.spill_bundle_id = spill_bundle.id
    spill_bundle.add_bundle(bundle.id)
    spill_bundle
  }
}

///|
/// Pre-compute loop depths for all blocks (O(blocks + edges))
/// Returns an array where loop_depths[block_id] = depth
pub fn compute_loop_depths(func : VCodeFunction) -> Array[Int] {
  let n = func.blocks.length()
  let depths : Array[Int] = Array::make(n, 0)

  // Count incoming backedges for each block
  for i, block in func.blocks {
    if block.terminator is Some(term) {
      // Get successors without allocating
      match term {
        Jump(target, _) => if i > target { depths[target] = depths[target] + 1 }
        Branch(_, then_b, else_b) => {
          if i > then_b {
            depths[then_b] = depths[then_b] + 1
          }
          if i > else_b {
            depths[else_b] = depths[else_b] + 1
          }
        }
        BranchCmp(_, _, _, _, then_b, else_b) => {
          if i > then_b {
            depths[then_b] = depths[then_b] + 1
          }
          if i > else_b {
            depths[else_b] = depths[else_b] + 1
          }
        }
        BranchZero(_, _, _, then_b, else_b) => {
          if i > then_b {
            depths[then_b] = depths[then_b] + 1
          }
          if i > else_b {
            depths[else_b] = depths[else_b] + 1
          }
        }
        BranchCmpImm(_, _, _, _, then_b, else_b) => {
          if i > then_b {
            depths[then_b] = depths[then_b] + 1
          }
          if i > else_b {
            depths[else_b] = depths[else_b] + 1
          }
        }
        BrTable(_, targets, default) => {
          for t in targets {
            if i > t {
              depths[t] = depths[t] + 1
            }
          }
          if i > default {
            depths[default] = depths[default] + 1
          }
        }
        Return(_) | Trap(_) => ()
      }
    }
  }

  // Cap depths at 3
  for i in 0..<n {
    if depths[i] > 3 {
      depths[i] = 3
    }
  }
  depths
}

///|
/// Compute spill weight for a bundle using pre-computed loop depths
/// Higher weight = more important to keep in register
pub fn compute_spill_weight(
  bundle : Bundle,
  ranges : LiveRangeSet,
  loop_depths : Array[Int],
) -> Double {
  let mut weight = 0.0
  for range_id in bundle.range_ids {
    let range = ranges.get(range_id)
    for use_pos in range.uses {
      // Base weight by use kind
      let base = match use_pos.kind {
        Def => 1.0
        Use => 1.0
      }

      // Loop depth multiplier (10x per nesting level)
      let loop_depth = loop_depths[use_pos.point.block]
      let depth_mult = @math.pow(10.0, loop_depth.to_double())
      weight += base * depth_mult
    }

    // Fixed register constraint bonus
    if range.has_fixed_constraint() {
      weight *= 10.0
    }

    // Cross-call penalty (harder to allocate)
    if range.crosses_call {
      weight *= 2.0
    }
  }

  // Normalize by total length (shorter = higher priority per instruction)
  let length = bundle.total_length(ranges)
  weight / length.to_double()
}

///|
/// Build initial bundles from LiveRanges
/// Each LiveRange starts in its own bundle
pub fn build_initial_bundles(ranges : LiveRangeSet) -> BundleSet {
  let result = BundleSet::new()
  for i in 0..<ranges.length() {
    let range = ranges.get(i)
    let bundle = Bundle::new(i, range.vreg.class)
    bundle.add_range(i)
    range.bundle_id = i
    result.add_bundle(bundle)
  }
  result
}
