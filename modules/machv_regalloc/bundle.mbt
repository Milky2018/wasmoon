// Ion-Style Bundle Data Structures
// Bundles group related LiveRanges for coalescing and allocation.

///|
/// A Bundle groups related LiveRanges that should ideally be allocated
/// to the same physical register. Bundles are formed by merging LiveRanges
/// connected by Move instructions, block arguments, or tied operands.
struct Bundle {
  id : Int
  mut spillset_id : Int // Original bundle ID before splitting (Cranelift-style spillset)
  range_ids : Array[Int] // Indices into LiveRangeSet
  mut merged_ranges : Array[ProgPointRange]? // Sorted merged ranges for fast regalloc span setup
  mut spill_weight : Int // Priority for allocation (higher = more important)
  mut prio : Int // Cached queue priority (total covered length)
  mut spill_bundle_id : Int // SpillBundle ID for split bundles (-1 if none)
  mut allocation : Allocation // Current allocation
  reg_class : @abi.RegClass // Register class for this bundle
  mut is_pinned : Bool // If true, cannot be evicted (e.g., function parameters)
  mut call_flags_ready : Bool // Lazy cache for call-crossing queries
  mut crosses_call_cached : Bool
  mut crosses_internal_call_cached : Bool
  mut crosses_foreign_call_cached : Bool
  mut requirement_flags_ready : Bool // Lazy cache for fixed-constraint queries
  mut has_fixed_constraint_cached : Bool
}

///|
pub fn Bundle::new(id : Int, reg_class : @abi.RegClass) -> Bundle {
  {
    id,
    spillset_id: id,
    range_ids: [],
    merged_ranges: None,
    spill_weight: 0,
    prio: 1,
    spill_bundle_id: -1,
    allocation: Unallocated,
    reg_class,
    is_pinned: false,
    call_flags_ready: false,
    crosses_call_cached: false,
    crosses_internal_call_cached: false,
    crosses_foreign_call_cached: false,
    requirement_flags_ready: false,
    has_fixed_constraint_cached: false,
  }
}

///|
/// Add a LiveRange to this bundle
fn Bundle::add_range(self : Bundle, range_id : Int) -> Unit {
  self.range_ids.push(range_id)
  self.merged_ranges = None
  self.call_flags_ready = false
  self.requirement_flags_ready = false
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
fn Bundle::ensure_requirement_flags(
  self : Bundle,
  ranges : LiveRangeSet,
) -> Unit {
  if self.requirement_flags_ready {
    return
  }
  let mut has_fixed = false
  for range_id in self.range_ids {
    if ranges.get(range_id).has_fixed_constraint() {
      has_fixed = true
      break
    }
  }
  self.has_fixed_constraint_cached = has_fixed
  self.requirement_flags_ready = true
}

///|
pub fn Bundle::has_fixed_constraint(
  self : Bundle,
  ranges : LiveRangeSet,
) -> Bool {
  self.ensure_requirement_flags(ranges)
  self.has_fixed_constraint_cached
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

///|
fn Bundle::ensure_call_flags(self : Bundle, ranges : LiveRangeSet) -> Unit {
  if self.call_flags_ready {
    return
  }
  let mut crosses_call = false
  let mut crosses_internal = false
  let mut crosses_foreign = false
  for range_id in self.range_ids {
    let range = ranges.get(range_id)
    crosses_call = crosses_call || range.crosses_call
    crosses_internal = crosses_internal || range.crosses_internal_call
    crosses_foreign = crosses_foreign || range.crosses_foreign_call
    if crosses_call && crosses_internal && crosses_foreign {
      break
    }
  }
  self.crosses_call_cached = crosses_call
  self.crosses_internal_call_cached = crosses_internal
  self.crosses_foreign_call_cached = crosses_foreign
  self.call_flags_ready = true
}

///|
/// Check if any range in this bundle crosses a function call
pub fn Bundle::crosses_call(self : Bundle, ranges : LiveRangeSet) -> Bool {
  self.ensure_call_flags(ranges)
  self.crosses_call_cached
}

///|
/// Check if any range in this bundle crosses an internal call
pub fn Bundle::crosses_internal_call(
  self : Bundle,
  ranges : LiveRangeSet,
) -> Bool {
  self.ensure_call_flags(ranges)
  self.crosses_internal_call_cached
}

///|
/// Check if any range in this bundle crosses a foreign/helper call
pub fn Bundle::crosses_foreign_call(
  self : Bundle,
  ranges : LiveRangeSet,
) -> Bool {
  self.ensure_call_flags(ranges)
  self.crosses_foreign_call_cached
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
    Vector => {
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
/// Pre-compute per-block approximate loop depth, aligned with regalloc2's
/// CFG heuristic (`cfg.rs::approx_loop_depth`): count backedge entries/exits
/// over linear block order and maintain a small nesting stack.
pub fn compute_loop_depths(func : @machv.Function) -> Array[Int] {
  let n = func.blocks.length()
  if n == 0 {
    return []
  }

  let backedge_in = Array::make(n, 0)
  let backedge_out = Array::make(n, 0)

  for block_idx, block in func.blocks {
    if block.terminator is Some(term) {
      fn add_backedge(
        backedge_in : Array[Int],
        backedge_out : Array[Int],
        block_idx : Int,
        succ : Int,
        n : Int,
      ) -> Unit {
        if succ < 0 || succ >= n {
          return
        }
        if succ <= block_idx {
          backedge_in[succ] = backedge_in[succ] + 1
          backedge_out[block_idx] = backedge_out[block_idx] + 1
        }
      }
      match term {
        Jump(target, _) =>
          add_backedge(backedge_in, backedge_out, block_idx, target, n)
        Branch(_, then_b, else_b) => {
          add_backedge(backedge_in, backedge_out, block_idx, then_b, n)
          add_backedge(backedge_in, backedge_out, block_idx, else_b, n)
        }
        BranchCmp(_, _, _, _, then_b, else_b)
        | BranchZero(_, _, _, then_b, else_b)
        | BranchCmpImm(_, _, _, _, then_b, else_b) => {
          add_backedge(backedge_in, backedge_out, block_idx, then_b, n)
          add_backedge(backedge_in, backedge_out, block_idx, else_b, n)
        }
        BrTable(_, targets, default) => {
          for target in targets {
            add_backedge(backedge_in, backedge_out, block_idx, target, n)
          }
          add_backedge(backedge_in, backedge_out, block_idx, default, n)
        }
        Return(_) | Trap(_) => ()
      }
    }
  }

  let depths : Array[Int] = []
  let backedge_stack : Array[Int] = []
  let mut cur_depth = 0

  for block_idx in 0..<n {
    if backedge_in[block_idx] > 0 {
      cur_depth = cur_depth + 1
      backedge_stack.push(backedge_in[block_idx])
    }

    depths.push(cur_depth)

    let mut out_count = backedge_out[block_idx]
    while backedge_stack.length() > 0 && out_count > 0 {
      out_count = out_count - 1
      let last = backedge_stack.length() - 1
      backedge_stack[last] = backedge_stack[last] - 1
      if backedge_stack[last] == 0 {
        cur_depth = cur_depth - 1
        backedge_stack.pop() |> ignore
      }
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
) -> Int {
  let mut weight = 0
  for range_id in bundle.range_ids {
    let range = ranges.get(range_id)
    for use_pos in range.uses {
      // Cranelift/regalloc2-like spill weights:
      // - hot loop bonus: 1000 * 4^depth (capped)
      // - def bonus: +2000
      // - operand constraint bonus: Any=+1000, FixedReg=+2000
      let mut depth = loop_depths[use_pos.point.block]
      if depth < 0 {
        depth = 0
      }
      if depth > 10 {
        depth = 10
      }
      let mut hot_bonus = 1000
      for _ in 0..<depth {
        hot_bonus = hot_bonus * 4
      }
      let def_bonus = match use_pos.kind {
        Def => 2000
        Use => 0
      }
      let constraint_bonus = match use_pos.constraint {
        AnyReg => 1000
        FixedReg(_) => 2000
      }
      weight = weight + hot_bonus + def_bonus + constraint_bonus
    }
  }
  if weight <= 0 {
    1
  } else {
    weight
  }
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
