// ============ Cranelift-style Edit Stream ============

///|
/// A move between two locations (register or spill slot).
struct RegMove {
  from : Loc
  to : Loc
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
/// Edits to insert before/after an instruction.
struct InstEdits {
  before : Array[RegMove]
  after : Array[RegMove]
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
  if moves.is_empty() {
    return moves
  }
  let result : Array[RegMove] = []
  let pending : Array[RegMove] = []
  let seen : Set[Int] = Set::new()
  fn same_loc(a : Loc, b : Loc) -> Bool {
    match (a, b) {
      (Reg(ra), Reg(rb)) => ra.index == rb.index && ra.class == rb.class
      (Spill(sa), Spill(sb)) => sa == sb
      _ => false
    }
  }

  fn class_key(cls : @abi.RegClass) -> Int {
    match cls {
      @abi.Int => 0
      @abi.Float32 => 1
      @abi.Float64 => 2
      @abi.Vector => 3
    }
  }

  fn loc_exact_key(loc : Loc) -> Int {
    match loc {
      Reg(preg) => 1_000_000 + preg.index * 4 + class_key(preg.class)
      Spill(slot) => slot
    }
  }

  fn pick_scratch_loc(class : @abi.RegClass, avoid_loc : Loc?) -> Loc {
    let mut avoid_idx : Int? = None
    match avoid_loc {
      Some(loc) =>
        match loc {
          Reg(preg) => avoid_idx = Some(preg.index)
          Spill(_) => ()
        }
      None => ()
    }
    let idx = match avoid_idx {
      Some(16) => 17
      _ => 16
    }
    Reg({ index: idx, class })
  }

  fn emit_stack_to_stack(mv : RegMove, result : Array[RegMove]) -> Unit {
    guard mv.from is Spill(from_slot) else { abort("expected stack src") }
    guard mv.to is Spill(to_slot) else { abort("expected stack dst") }
    let tmp = pick_scratch_loc(mv.class, None)
    // Load then store; keep them adjacent so the scratch value is not clobbered.
    result.push({ from: Spill(from_slot), to: tmp, class: mv.class })
    result.push({ from: tmp, to: Spill(to_slot), class: mv.class })
  }

  for mv in moves {
    // Skip identity moves.
    if !same_loc(mv.from, mv.to) {
      let k = (loc_exact_key(mv.from) * 131071 + loc_exact_key(mv.to)) * 8 +
        class_key(mv.class)
      if !seen.contains(k) {
        seen.add(k) |> ignore
        pending.push(mv)
      }
    }
  }
  if pending.length() <= 1 {
    if pending.length() == 1 &&
      pending[0].from is Spill(_) &&
      pending[0].to is Spill(_) {
      // Eliminate stack-to-stack even in the single-move case.
      let out : Array[RegMove] = []
      emit_stack_to_stack(pending[0], out)
      return out
    }
    return pending
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

  fn loc_key(loc : Loc) -> Int {
    match loc {
      Reg(preg) => preg.index * 2 + reg_kind(preg)
      Spill(slot) => 1_000_000 + slot
    }
  }

  fn aliases(a : Loc, b : Loc) -> Bool {
    loc_key(a) == loc_key(b)
  }

  // Build a set of source registers for quick lookup
  fn rebuild_src_set(pending : Array[RegMove]) -> Set[Int] {
    let srcs : Set[Int] = Set::new()
    for mv in pending {
      srcs.add(loc_key(mv.from))
    }
    srcs
  }

  // Iterate until all moves are resolved
  while pending.length() > 0 {
    let src_set = rebuild_src_set(pending)

    // Find a move whose destination is not a source of any other pending move
    let mut found_idx : Int? = None
    for i, mv in pending {
      let dest_key = loc_key(mv.to)
      if !src_set.contains(dest_key) {
        found_idx = Some(i)
        break
      }
    }
    match found_idx {
      Some(idx) => {
        // Safe to emit this move.
        let mv = pending.remove(idx)
        if mv.from is Spill(_) && mv.to is Spill(_) {
          emit_stack_to_stack(mv, result)
        } else {
          result.push(mv)
        }
      }
      None => {
        // All remaining moves form cycles. Break the cycle by saving one
        // destination register to a reserved scratch register, then continue.
        let mv = pending.remove(0)
        // Select a scratch register in the right bank that doesn't alias mv.to.
        let temp_loc : Loc = pick_scratch_loc(mv.class, Some(mv.to))

        // Save the destination's original value: temp <- dst
        result.push({ from: mv.to, to: temp_loc, class: mv.class })

        // Redirect all uses of the saved destination as a source to read from temp.
        for i in 0..<pending.length() {
          if aliases(pending[i].from, mv.to) {
            pending[i] = {
              from: temp_loc,
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
                    from: Reg(assigned_preg),
                    to: Reg(required_preg),
                    class: vreg.class,
                  })
                }
              // If already at required_preg, no move needed
              None =>
                // Spilled: need to reload to the required register
                if alloc.spill_slots.get(vreg.id) is Some(slot) {
                  // Encode spill slot as negative index in 'from'
                  // The emit phase will interpret this as a reload
                  edits.before.push({
                    from: Spill(slot),
                    to: Reg(required_preg),
                    class: vreg.class,
                  })
                }
            }
          } else if use_reg is @abi.Physical(preg) {
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
                    from: Reg(required_preg),
                    to: Reg(assigned_preg),
                    class: vreg.class,
                  })
                }
              None =>
                // Spilled: need to store from required register to spill slot
                if alloc.spill_slots.get(vreg.id) is Some(slot) {
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
        alloc.inst_edits.set((block_idx, inst_idx), edits)
      }
    }
  }
}
