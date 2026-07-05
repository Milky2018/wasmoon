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
  fn core_class(class : @abi.RegClass) -> @core_regalloc.RegClass {
    match class {
      Int => Int
      Float32 | Float64 => Float
      Vector => Vector
    }
  }

  fn class_tag(class : @abi.RegClass) -> Int {
    match class {
      Int => 0
      Float32 => 1
      Float64 => 2
      Vector => 3
    }
  }

  fn class_from_tag(tag : Int) -> @abi.RegClass {
    match tag {
      0 => Int
      1 => Float32
      2 => Float64
      3 => Vector
      _ => Int
    }
  }

  fn core_preg(preg : @abi.PReg) -> @core_regalloc.PhysicalReg {
    { id: preg.index, class: core_class(preg.class) }
  }

  fn core_location(vreg_id : Int) -> @core_regalloc.Location? {
    match alloc.assignments.get(vreg_id) {
      Some(preg) => Some(Reg(core_preg(preg)))
      None =>
        match alloc.spill_slots.get(vreg_id) {
          Some(slot) => Some(Spill(slot))
          None => None
        }
    }
  }

  fn old_loc(loc : @core_regalloc.Location, class : @abi.RegClass) -> Loc {
    match loc {
      Reg(preg) => Reg({ index: preg.id, class })
      Spill(slot) => Spill(slot)
    }
  }

  let fixed_insts : Array[@core_regalloc.FixedConstraintInst] = []
  for block_idx, block in func.blocks {
    for inst_idx, inst in block.insts {
      if inst.use_constraints.is_empty() && inst.def_constraints.is_empty() {
        continue
      }
      let uses : Array[@core_regalloc.FixedConstraint] = []
      let defs : Array[@core_regalloc.FixedConstraint] = []
      for i, constraint in inst.use_constraints {
        if constraint is FixedReg(required_preg) {
          let use_reg = inst.uses[i]
          if use_reg is Virtual(vreg) {
            uses.push({
              operand: Virtual(core_location(vreg.id), class_tag(vreg.class)),
              required: core_preg(required_preg),
            })
          } else if use_reg is Physical(preg) {
            uses.push({
              operand: Physical(core_preg(preg), class_tag(preg.class)),
              required: core_preg(required_preg),
            })
          }
        }
      }
      for i, constraint in inst.def_constraints {
        if constraint is FixedReg(required_preg) {
          let def = inst.defs[i]
          if def.reg is Virtual(vreg) {
            defs.push({
              operand: Virtual(core_location(vreg.id), class_tag(vreg.class)),
              required: core_preg(required_preg),
            })
          }
        }
      }
      fixed_insts.push({
        block_index: block_idx,
        inst_index: inst_idx,
        uses,
        defs,
      })
    }
  }
  let fixed_edits = @core_regalloc.plan_fixed_constraint_edits(fixed_insts)
  for edit in fixed_edits {
    let edits = InstEdits::new()
    for mv in edit.before {
      let class = class_from_tag(mv.class_tag)
      edits.before.push({
        from: old_loc(mv.from, class),
        to: old_loc(mv.to, class),
        class,
      })
    }
    for mv in edit.after {
      let class = class_from_tag(mv.class_tag)
      edits.after.push({
        from: old_loc(mv.from, class),
        to: old_loc(mv.to, class),
        class,
      })
    }
    alloc.inst_edits.push((edit.block_index, edit.inst_index, edits))
  }
}
