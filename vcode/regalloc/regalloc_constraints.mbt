// ============ RegMove for Constraint Processing ============

///|
/// A register move instruction (from regalloc constraint processing)
/// Move operation between registers
struct RegMove {
  from : @abi.PReg // Source register (or spill slot encoded as negative index)
  to : @abi.PReg // Destination register
  class : @abi.RegClass
}

///|
fn RegMove::to_string(self : RegMove) -> String {
  "mov \{self.to} <- \{self.from}"
}

///|
pub impl Show for RegMove with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Edits to insert before/after an instruction
/// Register constraint handling
struct InstEdits {
  before : Array[RegMove] // Moves to insert before the instruction
  after : Array[RegMove] // Moves to insert after the instruction
}

///|
fn InstEdits::new() -> InstEdits {
  { before: [], after: [] }
}

// ============ Parallel Move Resolver ============
// Resolves parallel moves to avoid conflicts when moves have cyclic dependencies.
// For example: X2->X3, X3->X2 cannot be executed in sequence without a temp.
// This implements a standard parallel move algorithm:
// 1. Find moves whose dest is not a src of any other move, emit those first
// 2. For cycles, use reserved scratch registers to break the cycle.

///|
/// Resolve parallel moves and emit them in the correct order.
/// Returns a list of moves that can be safely executed in sequence.
fn resolve_parallel_moves(moves : Array[RegMove]) -> Array[RegMove] {
  if moves.length() <= 1 {
    return moves
  }
  let result : Array[RegMove] = []
  let pending : Array[RegMove] = []
  for mv in moves {
    // Skip identity moves (same register index and same class)
    let same_class = match (mv.from.class, mv.to.class) {
      (@abi.Int, @abi.Int) => true
      (@abi.Float32, @abi.Float32) => true
      (@abi.Float64, @abi.Float64) => true
      _ => false
    }
    if mv.from.index != mv.to.index || not(same_class) {
      pending.push(mv)
    }
  }

  // Float32/Float64 registers alias the same Vn hardware register.
  // When resolving parallel moves we must treat them as the same location to
  // avoid clobbering (e.g. D1 <- D0 would overwrite S1).
  fn reg_kind(preg : @abi.PReg) -> Int {
    match preg.class {
      @abi.Int => 0
      @abi.Float32 | @abi.Float64 | @abi.Vector => 1 // Vector uses same Vn registers
    }
  }

  fn alias_key(preg : @abi.PReg) -> Int {
    preg.index * 2 + reg_kind(preg)
  }

  fn aliases(a : @abi.PReg, b : @abi.PReg) -> Bool {
    a.index == b.index && reg_kind(a) == reg_kind(b)
  }

  // Build a set of source registers for quick lookup
  fn rebuild_src_set(pending : Array[RegMove]) -> Set[Int] {
    let srcs : Set[Int] = Set::new()
    for mv in pending {
      if not(mv.from.is_spilled()) {
        srcs.add(alias_key(mv.from))
      }
    }
    srcs
  }

  fn make_key(preg : @abi.PReg) -> Int {
    alias_key(preg)
  }

  // Iterate until all moves are resolved
  while pending.length() > 0 {
    let src_set = rebuild_src_set(pending)

    // Find a move whose destination is not a source of any other pending move
    let mut found_idx : Int? = None
    for i, mv in pending {
      if mv.to.is_spilled() {
        // Spill destinations never conflict with register sources
        found_idx = Some(i)
        break
      }
      let dest_key = make_key(mv.to)
      if not(src_set.contains(dest_key)) {
        found_idx = Some(i)
        break
      }
    }
    match found_idx {
      Some(idx) =>
        // Safe to emit this move
        result.push(pending.remove(idx))
      None => {
        // All remaining moves form cycles. Break the cycle by saving one
        // destination register to a reserved scratch register, then continue.
        let mv = pending.remove(0)
        guard !mv.to.is_spilled() else {
          abort("cycle breaker requires register destination")
        }
        // Select a scratch register in the right bank that doesn't alias mv.to.
        let scratch_idx = if mv.to.index == 16 { 17 } else { 16 }
        let temp_preg : @abi.PReg = { index: scratch_idx, class: mv.to.class }

        // Save the destination's original value: temp <- dst
        result.push({ from: mv.to, to: temp_preg, class: mv.class })

        // Redirect all uses of the saved destination as a source to read from temp.
        for i in 0..<pending.length() {
          if !pending[i].from.is_spilled() && aliases(pending[i].from, mv.to) {
            pending[i] = {
              from: temp_preg,
              to: pending[i].to,
              class: pending[i].class,
            }
          }
        }

        // Re-add the original move; it should now be schedulable.
        pending.push(mv)
      }
    }
  }
  result
}

///|
/// Register allocation result
pub struct RegAllocResult {
  // Map from vreg id to assigned physical register
  assignments : Map[Int, @abi.PReg]
  // Map from vreg id to spill slot (if spilled)
  spill_slots : Map[Int, Int]
  // Total number of spill slots used
  num_spill_slots : Int
  // Constraint edits: (block_idx, inst_idx) -> edits to insert
  // Fixed register constraint handling
  inst_edits : Map[(Int, Int), InstEdits]
}

// ============ Reload Coalescing ============

///|
/// A reload interval tracks where a reloaded value can be kept alive
/// to eliminate redundant loads from the same spill slot
priv struct ReloadInterval {
  vreg_class : @abi.RegClass // Register class
  mut preg : @abi.PReg? // Allocated register (None = use scratch)
}

///|
/// Compute reload intervals for spilled values in each block
/// Returns a map: (block_idx, spill_slot) -> ReloadInterval
fn compute_reload_intervals(
  func : VCodeFunction,
  alloc : RegAllocResult,
) -> Map[(Int, Int), ReloadInterval] {
  let intervals : Map[(Int, Int), ReloadInterval] = {}
  for block_idx, block in func.blocks {
    // Track uses of spilled vregs in this block
    // Key: spill_slot, Value: (first_inst, last_inst, vreg_class)
    let slot_uses : Map[Int, (Int, Int, @abi.RegClass)] = {}
    for inst_idx, inst in block.insts {
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          if alloc.spill_slots.get(vreg.id) is Some(slot) {
            // Do not reload-coalesce vector values: there is no safe
            // non-allocatable vector scratch register bank, and AAPCS64 only
            // guarantees preserving the low 64 bits of V8-V15.
            if vreg.class is @abi.Vector {
              continue
            }
            match slot_uses.get(slot) {
              Some((first, _, cls)) =>
                slot_uses.set(slot, (first, inst_idx, cls))
              None => slot_uses.set(slot, (inst_idx, inst_idx, vreg.class))
            }
          }
        }
      }
    }
    // Create reload intervals for slots used multiple times
    for slot, info in slot_uses {
      let (first_inst, last_inst, vreg_class) = info
      if last_inst > first_inst {
        // Multiple uses - worth coalescing
        intervals.set((block_idx, slot), { vreg_class, preg: None })
      }
    }
  }
  intervals
}

///|
/// Try to allocate registers for reload intervals
/// Uses callee-saved registers that aren't already in use
fn allocate_reload_registers(
  func : VCodeFunction,
  alloc : RegAllocResult,
  intervals : Map[(Int, Int), ReloadInterval],
) -> Unit {
  // Collect which registers are already allocated to virtual registers.
  // Reload coalescing must NOT clobber any register that the allocator uses
  // (including live-ins like vmctx), otherwise a StackLoad can overwrite a
  // still-live value and cause memory corruption / traps.
  let used_int_regs : @hashset.HashSet[Int] = @hashset.HashSet::new()
  let used_float_regs : @hashset.HashSet[Int] = @hashset.HashSet::new()
  for _, preg in alloc.assignments {
    match preg.class {
      @abi.Int => used_int_regs.add(preg.index) |> ignore
      _ => used_float_regs.add(preg.index) |> ignore
    }
  }

  // Reserve special registers that are not part of the allocator pool but are
  // used by the ABI / codegen.
  // - X19 is reserved for vmctx-related loads in the prologue when needed.
  used_int_regs.add(19) |> ignore
  // - X21 is the pinned VMContext register (enable_pinned_reg).
  used_int_regs.add(@abi.REG_VMCTX) |> ignore
  // - X20 is reserved for cached memory0 descriptor pointer when needed.
  if func.uses_mem0() {
    used_int_regs.add(@abi.REG_MEM0_DESC) |> ignore
  }
  // - X23 is reserved for extra_results_buffer when needed.
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let needs_x23_reserved = needs_extra || calls_multi
  if needs_x23_reserved {
    used_int_regs.add(23) |> ignore
  }

  // Candidate callee-saved registers for reload coalescing.
  // Only use registers that are NOT allocated to any vreg to avoid clobbering
  // live values (including parameters that may stay live across a block).
  let reload_int_regs = [20, 22, 23, 24, 25, 26, 27, 28]
  let reload_float_regs = [8, 9, 10, 11, 12, 13, 14, 15]

  // Per-block allocation to avoid conflicts within a block
  for block_idx, _block in func.blocks {
    // Track which reload registers are in use within this block
    let block_int_used : @hashset.HashSet[Int] = @hashset.HashSet::new()
    let block_float_used : @hashset.HashSet[Int] = @hashset.HashSet::new()
    // Allocate reload registers for intervals in this block
    for key, interval in intervals {
      let (b_idx, _) = key
      if b_idx != block_idx {
        continue
      }
      match interval.vreg_class {
        @abi.Int =>
          for idx in reload_int_regs {
            if used_int_regs.contains(idx) || block_int_used.contains(idx) {
              continue
            }
            interval.preg = Some({ index: idx, class: interval.vreg_class })
            block_int_used.add(idx) |> ignore
            break
          }
        @abi.Vector => ()
        _ =>
          for idx in reload_float_regs {
            if used_float_regs.contains(idx) || block_float_used.contains(idx) {
              continue
            }
            interval.preg = Some({ index: idx, class: interval.vreg_class })
            block_float_used.add(idx) |> ignore
            break
          }
      }
    }
  }
}

// ============ Constraint Processing ============

///|
/// Process operand constraints and generate RegMove edits
/// Design: constraints are processed after allocation
/// and moves are inserted when the allocated register doesn't match the constraint
pub fn process_constraints(
  func : VCodeFunction,
  alloc : RegAllocResult,
) -> Unit {
  for block_idx, block in func.blocks {
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
            match alloc.assignments.get(vreg.id) {
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
                if alloc.spill_slots.get(vreg.id) is Some(slot) {
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
          } else if use_reg is @abi.Physical(preg) {
            if preg.index != required_preg.index {
              edits.before.push({
                from: preg,
                to: required_preg,
                class: preg.class,
              })
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
            match alloc.assignments.get(vreg.id) {
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
                if alloc.spill_slots.get(vreg.id) is Some(slot) {
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
      if !edits.before.is_empty() || !edits.after.is_empty() {
        alloc.inst_edits.set((block_idx, inst_idx), edits)
      }
    }
  }
}
