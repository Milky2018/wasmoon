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
pub impl Show for RegMove with fn output(self, logger) {
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
  let isa = @isa.ISA::current()
  let machine_env = isa.machine_env()

  fn to_core_class(cls : @abi.RegClass) -> @core_regalloc.RegClass {
    match cls {
      Int => Int
      Float32 | Float64 => Float
      Vector => Vector
    }
  }

  fn to_core_preg(preg : @abi.PReg) -> @core_regalloc.PhysicalReg {
    { id: preg.index, class: to_core_class(preg.class) }
  }

  fn to_core_loc(loc : Loc) -> @core_regalloc.Location {
    match loc {
      Reg(preg) => Reg(to_core_preg(preg))
      Spill(slot) => Spill(slot)
    }
  }

  fn to_core_move(mv : RegMove) -> @core_regalloc.ParallelMove {
    {
      from: to_core_loc(mv.from),
      to: to_core_loc(mv.to),
      class: to_core_class(mv.class),
    }
  }

  fn from_core_loc(
    loc : @core_regalloc.Location,
    class : @abi.RegClass,
  ) -> Loc {
    match loc {
      Reg(preg) => Reg({ index: preg.id, class })
      Spill(slot) => Spill(slot)
    }
  }

  fn from_core_move(
    mv : @core_regalloc.ParallelMove,
    class : @abi.RegClass,
  ) -> RegMove {
    {
      from: from_core_loc(mv.from, class),
      to: from_core_loc(mv.to, class),
      class,
    }
  }

  let core_moves : Array[@core_regalloc.ParallelMove] = []
  for mv in moves {
    core_moves.push(to_core_move(mv))
  }

  fn scratch_int_regs() -> Array[@core_regalloc.PhysicalReg] {
    machine_env.scratch_int.map(fn(id) { { id, class: Int } })
  }

  fn scratch_float_regs() -> Array[@core_regalloc.PhysicalReg] {
    machine_env.scratch_float.map(fn(id) { { id, class: Float } })
  }

  let resolved = @core_regalloc.resolve_parallel_moves(
    core_moves,
    scratch_int_regs(),
    scratch_float_regs(),
  )
  let result : Array[RegMove] = []

  fn fallback_class(class : @core_regalloc.RegClass) -> @abi.RegClass {
    match class {
      Int => Int
      Float => {
        for old in moves {
          if old.class is Float32 || old.class is Float64 {
            return old.class
          }
        }
        Float64
      }
      Vector => Vector
    }
  }

  fn class_for_resolved_move(
    mv : @core_regalloc.ParallelMove,
  ) -> @abi.RegClass {
    for old in moves {
      if to_core_loc(old.from) == mv.from && to_core_loc(old.to) == mv.to {
        return old.class
      }
    }
    fallback_class(mv.class)
  }

  for mv in resolved {
    let class = class_for_resolved_move(mv)
    result.push(from_core_move(mv, class))
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
  // Constraint edits as a linear stream of (block_idx, inst_idx, edits),
  // aligned with regalloc2's position-sorted edit storage model.
  inst_edits : Array[(Int, Int, InstEdits)]
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
        if constraint is FixedReg(required_preg) {
          let use_reg = inst.uses[i]
          if use_reg is Virtual(vreg) {
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
        alloc.inst_edits.push((block_idx, inst_idx, edits))
      }
    }
  }
}
