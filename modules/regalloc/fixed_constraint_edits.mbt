///|
pub(all) enum FixedConstraintOperand {
  Virtual(Location?, Int)
  Physical(PhysicalReg, Int)
} derive(Eq, Debug)

///|
pub(all) struct FixedConstraint {
  operand : FixedConstraintOperand
  required : PhysicalReg
} derive(Eq, Debug)

///|
pub(all) struct FixedConstraintInst {
  block_index : Int
  inst_index : Int
  uses : Array[FixedConstraint]
  defs : Array[FixedConstraint]
} derive(Debug)

///|
pub(all) struct FixedConstraintMove {
  from : Location
  to : Location
  class_tag : Int
} derive(Eq, Debug)

///|
pub(all) struct FixedConstraintInstEdits {
  block_index : Int
  inst_index : Int
  before : Array[FixedConstraintMove]
  after : Array[FixedConstraintMove]
} derive(Debug)

///|
fn fixed_constraint_same_reg(a : PhysicalReg, b : PhysicalReg) -> Bool {
  a.id == b.id
}

///|
fn fixed_constraint_use_move(
  constraint : FixedConstraint,
) -> FixedConstraintMove? {
  match constraint.operand {
    Virtual(location, class_tag) =>
      match location {
        Some(Reg(preg)) =>
          if fixed_constraint_same_reg(preg, constraint.required) {
            None
          } else {
            Some({ from: Reg(preg), to: Reg(constraint.required), class_tag })
          }
        Some(Spill(slot)) =>
          Some({ from: Spill(slot), to: Reg(constraint.required), class_tag })
        None => None
      }
    Physical(preg, class_tag) =>
      if fixed_constraint_same_reg(preg, constraint.required) {
        None
      } else {
        Some({ from: Reg(preg), to: Reg(constraint.required), class_tag })
      }
  }
}

///|
fn fixed_constraint_def_move(
  constraint : FixedConstraint,
) -> FixedConstraintMove? {
  match constraint.operand {
    Virtual(location, class_tag) =>
      match location {
        Some(Reg(preg)) =>
          if fixed_constraint_same_reg(preg, constraint.required) {
            None
          } else {
            Some({ from: Reg(constraint.required), to: Reg(preg), class_tag })
          }
        Some(Spill(slot)) =>
          Some({ from: Reg(constraint.required), to: Spill(slot), class_tag })
        None => None
      }
    Physical(_, _) => None
  }
}

///|
pub fn plan_fixed_constraint_edits(
  insts : Array[FixedConstraintInst],
) -> Array[FixedConstraintInstEdits] {
  let edits : Array[FixedConstraintInstEdits] = []
  for inst in insts {
    let before : Array[FixedConstraintMove] = []
    let after : Array[FixedConstraintMove] = []
    for constraint in inst.uses {
      if fixed_constraint_use_move(constraint) is Some(mv) {
        before.push(mv)
      }
    }
    for constraint in inst.defs {
      if fixed_constraint_def_move(constraint) is Some(mv) {
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
