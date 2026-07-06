///|
pub(all) enum BacktrackingAllocationLoc[P] {
  BacktrackingReg(P)
  BacktrackingSpill(Int)
  BacktrackingUnallocated
}

///|
pub(all) struct BacktrackingRangeResult[P] {
  vreg_id : Int
  allocation : BacktrackingAllocationLoc[P]
}

///|
pub(all) struct BacktrackingAllocationResult[P] {
  assignments : Array[(Int, P)]
  spill_slots : Array[(Int, Int)]
  num_spill_slots : Int
}

///|
pub fn[P] build_backtracking_allocation_result(
  ranges : Array[BacktrackingRangeResult[P]],
  num_spill_slots : Int,
) -> BacktrackingAllocationResult[P] {
  let assignments : Array[(Int, P)] = []
  let spill_slots : Array[(Int, Int)] = []
  for range in ranges {
    match range.allocation {
      BacktrackingReg(preg) => assignments.push((range.vreg_id, preg))
      BacktrackingSpill(slot) => spill_slots.push((range.vreg_id, slot))
      BacktrackingUnallocated => ()
    }
  }
  { assignments, spill_slots, num_spill_slots }
}

///|
pub(all) enum BacktrackingMoveLoc[P] {
  BacktrackingMoveReg(P)
  BacktrackingMoveSpill(Int)
}

///|
pub(all) enum BacktrackingConstraintOperand[P] {
  BacktrackingVirtual(BacktrackingAllocationLoc[P], Int)
  BacktrackingPhysical(P, Int)
}

///|
pub(all) struct BacktrackingFixedConstraint[P] {
  operand : BacktrackingConstraintOperand[P]
  required : P
}

///|
pub(all) struct BacktrackingFixedConstraintInst[P] {
  block_index : Int
  inst_index : Int
  uses : Array[BacktrackingFixedConstraint[P]]
  defs : Array[BacktrackingFixedConstraint[P]]
}

///|
pub(all) struct BacktrackingConstraintMove[P] {
  from : BacktrackingMoveLoc[P]
  to : BacktrackingMoveLoc[P]
  class_tag : Int
}

///|
pub(all) struct BacktrackingConstraintInstEdits[P] {
  block_index : Int
  inst_index : Int
  before : Array[BacktrackingConstraintMove[P]]
  after : Array[BacktrackingConstraintMove[P]]
}

///|
fn[P] backtracking_fixed_constraint_use_move(
  constraint : BacktrackingFixedConstraint[P],
  same_reg : (P, P) -> Bool,
) -> BacktrackingConstraintMove[P]? {
  match constraint.operand {
    BacktrackingVirtual(location, class_tag) =>
      match location {
        BacktrackingReg(preg) =>
          if same_reg(preg, constraint.required) {
            None
          } else {
            Some({
              from: BacktrackingMoveReg(preg),
              to: BacktrackingMoveReg(constraint.required),
              class_tag,
            })
          }
        BacktrackingSpill(slot) =>
          Some({
            from: BacktrackingMoveSpill(slot),
            to: BacktrackingMoveReg(constraint.required),
            class_tag,
          })
        BacktrackingUnallocated => None
      }
    BacktrackingPhysical(preg, class_tag) =>
      if same_reg(preg, constraint.required) {
        None
      } else {
        Some({
          from: BacktrackingMoveReg(preg),
          to: BacktrackingMoveReg(constraint.required),
          class_tag,
        })
      }
  }
}

///|
fn[P] backtracking_fixed_constraint_def_move(
  constraint : BacktrackingFixedConstraint[P],
  same_reg : (P, P) -> Bool,
) -> BacktrackingConstraintMove[P]? {
  match constraint.operand {
    BacktrackingVirtual(location, class_tag) =>
      match location {
        BacktrackingReg(preg) =>
          if same_reg(preg, constraint.required) {
            None
          } else {
            Some({
              from: BacktrackingMoveReg(constraint.required),
              to: BacktrackingMoveReg(preg),
              class_tag,
            })
          }
        BacktrackingSpill(slot) =>
          Some({
            from: BacktrackingMoveReg(constraint.required),
            to: BacktrackingMoveSpill(slot),
            class_tag,
          })
        BacktrackingUnallocated => None
      }
    BacktrackingPhysical(_, _) => None
  }
}

///|
pub fn[P] plan_backtracking_fixed_constraint_edits(
  insts : Array[BacktrackingFixedConstraintInst[P]],
  same_reg : (P, P) -> Bool,
) -> Array[BacktrackingConstraintInstEdits[P]] {
  let edits : Array[BacktrackingConstraintInstEdits[P]] = []
  for inst in insts {
    let before : Array[BacktrackingConstraintMove[P]] = []
    let after : Array[BacktrackingConstraintMove[P]] = []
    for constraint in inst.uses {
      if backtracking_fixed_constraint_use_move(constraint, same_reg)
        is Some(mv) {
        before.push(mv)
      }
    }
    for constraint in inst.defs {
      if backtracking_fixed_constraint_def_move(constraint, same_reg)
        is Some(mv) {
        after.push(mv)
      }
    }
    if !before.is_empty() || !after.is_empty() {
      edits.push({
        block_index: inst.block_index,
        inst_index: inst.inst_index,
        before,
        after,
      })
    }
  }
  edits
}
